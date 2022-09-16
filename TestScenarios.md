**#** | **Category** | **Description** | Priority |   |
|--- | --- | --- | --- | --- |
| 001 | Basic LB | Single internal front end |   |   |
| 002 | Multiple internal front ends |   |   |
| 003 | Single public front end |   |   |
| 004 | Multiple public front ends |   |   |
| 005 | Single backend pool |   |   |
| 006 | Multiple backend pools |   |   |
| 007 | Inbound NAT rules defined |   |   |
| 008 | Inbound NAT pools defined |   |   |
| 009 | Backend pool contains VMSS |   |   |
| 010 | Public IP is basic SKU |   |   |
| 011 | Public IP is dynamic |   |   |
| 012 | Public IP is IPv6 |   |   |
| 013 | Skip migrating FE Ips to new LB |   | low |   |
| 014 | Migrate basic FE IP addresses to alternates in same subnet |   | low |   |
| 015 | Standard LB | Standard LB name in use |   |   |
| 016 | Use existing Standard LB |   |  low |   |
| 017 | VMSS | Member of multiple backend pools |   |   |
| 018 | Member of backend pools from multiple LBs (internal/public) |   |   |
| 019 | Upgrade policy: manual |   |   |
| 020 | Upgrade policy: automatic |   |   |
| 021 | Upgrade policy: rollout |   |   |
| 022 | No NSG associated with VMSS NICs |   |   |
| 023 | NSG associated with VMSS NICs with security rule allowing backend traffic |   |   |
| 024 | NSG associated with VMSS NICs without security rule allowing backend traffic |   |   |
| 025 | VMSS contains instance with instance(s) protection (scale set actions) configured |   |   |
| 026 | VMSS has 100 instances |   |   |
| 027 | ~~VMSS is large (\> 100 instances) and uses multiple placement groups (requires standard LB)~~ |   |   |
| 028| VMs | Member of availability set |   |   |