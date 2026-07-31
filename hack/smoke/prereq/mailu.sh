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
