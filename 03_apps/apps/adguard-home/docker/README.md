# AdGuard Home Docker Setup

This directory contains a Docker-based setup for AdGuard Home that mirrors the Kubernetes deployment configuration but runs on a separate Raspberry Pi for redundancy.

## Purpose

While the main AdGuard Home instance runs in the Kubernetes cluster, this Docker setup provides:
- **Backup DNS resolver** in case the cluster is down
- **Redundancy** for critical DNS services
- **Independent operation** on Raspberry Pi hardware

The configuration is kept similar to the Kubernetes deployment to maintain consistency in DNS filtering rules and settings.
