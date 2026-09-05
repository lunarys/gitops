kubectl patch pv "$1" -p '{"spec":{"claimRef": null}}'
