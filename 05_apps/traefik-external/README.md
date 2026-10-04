This is a separate instance of traefik for handling requests from the external internet.
It is its own chart, but deliberately close to the internal instance
(`02_bootstrap/03_traefik`): same traefik chart version and mostly the same base settings.

This way, this instance can receive different network policies,
that are more restrictive than my internal traefik deployment.
Additionally, different middlewares can be preconfigured for both instances.

Through separate ingress classes, the traefik instance can easily be switched for
restricted internal access or general external access.
