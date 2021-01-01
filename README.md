# Home Assistant Add-on Hashicorp Vault

[![GitHub Release](https://img.shields.io/github/v/release/tidalf/ha-addon-vault)](https://github.com/tidalf/ha-addon-vault/releases)
[![Build status](https://img.shields.io/github/workflow/status/tidalf/ha-addon-vault/Build%20plugin/main)](https://github.com/tidalf/ha-addon-vault/actions)
![Top language](https://img.shields.io/github/languages/top/tidalf/ha-addon-vault)
![License](https://img.shields.io/github/license/tidalf/ha-addon-vault)

### Summary

- Launch an Hashicorp vault server in raft mode. 
- The default ssl key from /ssl is used if it exists.
- TLS can be disabled by setting "disable_tls" to true :
```bash
disable_tls: true
```

### Install

Use the following repository (add it in the add-on store of the supervisor) : 
https://github.com/tidalf/ha-addons


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

### Unsafe auto unseal
- You can enable unsafe auto unseal (it'll store the unseal keys and root token in clear in /data/vault/vault.ini), it'll run a terraform config)
```bash
unsafe_auto_init: true
```
- You can create a default user with an admin policy attached by using the following config: 
```bash
create_admin_user: true
vault_admin_user: admin
vault_admin_password: some_password
```

### Use keybase handle to encrypt initial keys
- You can enable auto initialization with gpg/keybase keys:
```bash
pgp_keys: 'keybase:exampleuser'
```
- the encrypted variables are shown in the log (fixme?)
- if you use keybase and no kms autounseal you'll need to unseal manually
```bash
export VAULT_ADDR="http(s)://yourinstance:8200"
vault operator unseal [-migrate] $(echo $unsealkey | base64 -d | keybase pgp decrypt)
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

If you disable aws kms, you need to set the downgrade variable (at least for the transition) (fixme)
```bash
aws_unseal: false
aws_unseal_downgrade: true
```
