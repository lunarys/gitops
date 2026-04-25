The crowdsec agent failed because there were too many file watchers already.

- https://github.com/TheDuffman85/crowdsec-web-ui?tab=readme-ov-file
- https://discourse.crowdsec.net/t/error-could-not-create-fsnotify-watcher-too-many-open-files-kubernetes/1584/8


```bash
cat /proc/sys/fs/inotify/max_user_watches
cat /proc/sys/fs/inotify/max_user_instances
cat /proc/sys/fs/inotify/max_queued_events

sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=512

echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.d/inotify-limit.conf
echo "fs.inotify.max_user_instances=512" | sudo tee -a /etc/sysctl.d/inotify-limit.conf

sudo sysctl --system
```
