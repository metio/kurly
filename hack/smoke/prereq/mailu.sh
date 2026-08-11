# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# All six mailu components mount ONE shared volume and none of them creates it —
# the claim is the operator's to provide, which is what makes the parts a single
# mail system rather than six unrelated servers. Without it every stage sits
# Pending on "persistentvolumeclaim mailu-storage not found".
#
# Sourced with $ns set, by the fast scenario and the deep check alike.

: "${ns:?prerequisites are sourced by kurly::prereq, which sets ns}"

kubectl --namespace="$ns" apply --filename=- <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: mailu-storage }
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 2Gi } }
EOF

# A DNSSEC-VALIDATING RESOLVER, which the cluster's own does not do. Mailu's admin
# refuses to run without one: it logs "Your DNS resolver at <kube-dns> isn't doing
# DNSSEC validation" at CRITICAL and terminates itself, so the component looks like
# it crashed rather than like it declined. Mailu ships exactly this resolver for
# the purpose, and every stage takes its address as resolverAddress.
kubedns="$(kubectl --namespace=kube-system get service kube-dns -o jsonpath='{.spec.clusterIP}')"
sed "s/KUBEDNS/${kubedns}/g" <<'EOF2' | kubectl --namespace="$ns" apply --filename=-
apiVersion: apps/v1
kind: Deployment
metadata: { name: mailu-resolver, labels: { app: mailu-resolver } }
spec:
  replicas: 1
  selector: { matchLabels: { app: mailu-resolver } }
  template:
    metadata: { labels: { app: mailu-resolver } }
    spec:
      containers:
        - name: unbound
          image: ghcr.io/mailu/unbound:2024.06
          # The image's own /start.py templates a recursive DNSSEC resolver and
          # execs unbound. That config is replaced here and unbound run directly,
          # for one addition it cannot express: a stub zone sending cluster.local
          # to the cluster's DNS. Mailu's pods have to be POINTED at this resolver
          # to satisfy the DNSSEC check, and a resolver that cannot answer
          # cluster.local leaves them unable to find each other — swapping one
          # failure for another. cluster.local is also marked insecure, or DNSSEC
          # validation rejects an internal zone that is not signed and never will
          # be. The image's own root.hints and trusted-key.key are kept.
          command: ["unbound", "-d", "-c", "/conf/unbound.conf"]
          volumeMounts:
            - { name: conf, mountPath: /conf }
          ports:
            - { containerPort: 53, protocol: UDP }
            - { containerPort: 53, protocol: TCP }
          readinessProbe:
            tcpSocket: { port: 53 }
            periodSeconds: 5
      volumes:
        - name: conf
          configMap: { name: mailu-resolver-conf }
---
apiVersion: v1
kind: ConfigMap
metadata: { name: mailu-resolver-conf }
data:
  unbound.conf: |
    server:
      verbosity: 1
      interface: 0.0.0.0
      do-ip4: yes
      do-ip6: no
      do-udp: yes
      do-tcp: yes
      do-daemonize: no
      access-control: 10.0.0.0/8 allow
      directory: "/etc/unbound"
      username: ""
      auto-trust-anchor-file: "/etc/unbound/trusted-key.key"
      root-hints: "/etc/unbound/root.hints"
      hide-identity: yes
      hide-version: yes
      domain-insecure: "cluster.local"
      domain-insecure: "in-addr.arpa"
    stub-zone:
      name: "cluster.local"
      stub-addr: KUBEDNS
    stub-zone:
      name: "in-addr.arpa"
      stub-addr: KUBEDNS
---
apiVersion: v1
kind: Service
metadata: { name: mailu-resolver }
spec:
  selector: { app: mailu-resolver }
  ports:
    - { name: dns-udp, port: 53, targetPort: 53, protocol: UDP }
    - { name: dns-tcp, port: 53, targetPort: 53, protocol: TCP }
EOF2
kubectl --namespace="$ns" rollout status deployment/mailu-resolver --timeout=180s
