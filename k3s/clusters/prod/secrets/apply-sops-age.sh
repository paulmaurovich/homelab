cat ~/homelab.agekey | kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=homelab.agekey=/dev/stdin
