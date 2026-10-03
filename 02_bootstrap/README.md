The integral components to get a cluster moving initially:

    - Cilium, to get the network working.
    - ArgoCD, to deploy stuff.
    - Manual secrets, such as GitHub and Bitwarden, that are required to bootstrap anything else. 
      These must be deployed manually to automatically retrieve everything else.
    - Traefik, as an ingress controller, to access ArgoCD.
