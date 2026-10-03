https://github.com/rancher/local-path-provisioner

**Storage class adjustments**: https://github.com/rancher/local-path-provisioner?tab=readme-ov-file#storage-classes

- pathPattern could exclude pv name, maybe helps transparently reusing the directory
- reclaimPolicy `Retain` -> `Delete`?

# Possible alternatives

From https://kubernetes-csi.github.io/docs/drivers.html

- https://github.com/alibaba/open-local
- https://github.com/hwameistor/hwameistor?tab=readme-ov-file#local-disk-manager
