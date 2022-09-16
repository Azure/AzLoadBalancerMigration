# Recovery Procedure

In order to move frontend IP addresses to the new 'standard' SKU load balancer, the 'basic' SKU load balancer must either be completely de-configured or deleted,
and this module takes the delete approach. Therefore, almost all recovery scenarios following a failed migration is a fail-forward approach.

Upon execution, this module takes a backup of the specified 'basic' SKU load balancer, to be used in retrying a failed migration.  Using this backup file in a
retry is effectively the same as the pre-migration state. 

To recover from a failed migration, first address the cause of the initial failure (such as permissions, misconfiguration, etc) described in the encountered error 
message, then you must pass the script the path of the 'basic' SKU load balancer backup file during execution. The backup file will be created
either in the current working directory where the module was executed, or at the path specified with `-RecoveryBackupPath <path>` in the initial execution, and will
be named following the pattern `State_<basicLBName>_<basicLBResourceGroupName>_<timestamp>.json`. 