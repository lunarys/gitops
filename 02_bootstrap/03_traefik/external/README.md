This is a separate instance of traefik for handling requests from the external internet.
It uses the same base settings, but relevant values are overridden via the Argo Application.

This way, this instance can receive different network policies,
that are more restrictive than my internal traefik deployment.
Additionally, different middlewares can be preconfigured for both instances.

Through separate ingress classes, the traefik instance can easily be switched for
restricted internal access or general external access.
