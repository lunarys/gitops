#sudo ~/k0sctl-linux-amd64 apply -c k0s-test-cluster-config.yaml

k0sctl apply --config k0s-test-cluster.yaml --config k0s-cluster-config.yaml

# TODO: --kubeconfig-out ~/.kube/config
# TODO: --kubeconfig-cluster	Set kubernetes cluster name
