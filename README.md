# Home Assistant Add-on Hashicorp Vault

### Summary

- Launch an Hashicorp vault server in raft mode. 
- The default ssl key from /ssl is used if it exists.
- TLS can be disabled by setting "disable_tls" to true :
```bash
disable_tls: true
```

### Enable the cluster
Cluster listener addr is set to localhost by default. 

Set it to a valid address through 'vault_cluster_addr' then enable the port forward for tcp/8201 (provide a value for the port)

### Custom the configuration
- You can use the vault_local_config variable (see https://hub.docker.com/_/vault)
- The raft data is stored in /data/vault/raft, it'll be removed if you remove the addon. 
- You can change that by using the raft_path setting
```bash
raft_path: /config/vault/raft
```

### Use AWS KMS for autounseal
It's possible to use the AWS KMS service to auto unseal the vault. 
You'll need to create the kms key and the iam user credentials with correct policy (kms:Encrypt,kms:Decrypt and kms:DescribeKey).

Then you can set the following values:
```bash
aws_unseal: true
aws_region: eu-west-1
aws_access_key: *****
aws_secret_key: ******
aws_kms_key_id: ******
```
