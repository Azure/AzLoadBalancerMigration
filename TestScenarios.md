| **Category** | **Description** | Priority |   |
| --- | --- | --- | --- |
| Basic LB | Single internal front end |   |   |
|   | Multiple internal front ends |   |   |
|   | Single public front end |   |   |
|   | Multiple public front ends |   |   |
|   | Single backend pool |   |   |
|   | Multiple backend pools |   |   |
|   | Inbound NAT rules defined |   |   |
|   | Inbound NAT pools defined |   |   |
|   | Backend pool contains VMSS |   |   |
|   | Public IP is basic SKU |   |   |
|   | Public IP is dynamic |   |   |
|   | Public IP is IPv6 |   |   |
|   | Skip migrating FE Ips to new LB | low |   |
|   | Migrate basic FE IP addresses to alternates in same subnet | low |   |
| Standard LB | Standard LB name in use |   |   |
|   | Use existing Standard LB | low |   |
| VMSS | Member of multiple backend pools |   |   |
|   | Member of backend pools from multiple LBs (internal/public) |   |   |
|   | Upgrade policy: manual |   |   |
|   | Upgrade policy: automatic |   |   |
|   | Upgrade policy: rollout |   |   |
|   | No NSG associated with VMSS NICs |   |   |
|   | NSG associated with VMSS NICs with security rule allowing backend traffic |   |   |
|   | NSG associated with VMSS NICs without security rule allowing backend traffic |   |   |
|   | VMSS contains instance with instance(s) protection (scale set actions) configured |   |   |
|   | VMSS has 100 instances |   |   |
|   | ~~VMSS is large (\> 100 instances) and uses multiple placement groups (requires standard LB)~~ |   |   |
| VMs | Member of availability set |   |   |