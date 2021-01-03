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


### Custom the configuration
- You can use the vault_local_config variable (see https://hub.docker.com/_/vault)
- The raft data is stored in /data/vault/raft, it'll be removed if you remove the addon. 
- You can change that by using the raft_path setting (it'll probably break the other scripts)
```bash
raft_path: /config/vault/raft
```


### Unsafe auto unseal
- You can enable unsafe auto unseal (it'll store the unseal keys and root token in clear in /data/vault/vault.ini)
```bash
unsafe_auto_init: true
```

### Auto provisioning
- You can enable initial config of the vault: It'll run a terraform config (it can be in changed in /config/vault/terraform)
```bash
auto_provision: true
```
- If you don't use unsafe auto unseal (it stores a token), you can specify a provisioning token (make it short lived)
````
provision_token: a_token
````

- You can create a default user with an admin policy attached like that: 
```bash
create_admin_user: true
vault_admin_user: admin
vault_admin_password: some_password
```

### Use keybase to encrypt initial keys
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
* It's possible to use the AWS KMS service to auto unseal the vault. 
* You'll need to create the kms key and the iam user credentials with correct policy (kms:Encrypt,kms:Decrypt and kms:DescribeKey).
* Then you can set the following values:
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

### Enable the cluster
Cluster listener addr is set to localhost by default. 

Set it to a valid address through 'vault_cluster_addr' then enable the port forward for tcp/8201 (provide a value for the port)
(it's untested, no automated setup for multi nodes for now)

### Downgrading from keybase to unsafe local storage
It's a bit tricky and those commands need to be exec outside of the addon container: 

- Retrieve the needed values from the logs (keys_b64, encoded_root_token and adm.asc)
- Config your local vault client to reach your vault server addon (export VAULT_ADDR=..)
- Unseal the vault using your keybase
- Create a provisioning token
- Set it in the config, restart
- Start the rekeing using a backup
- The script will retrieve the backup using the provisioning token above.
```bash
#!/usr/bin/env bash
# $1 is the encrypted unseal key (keys_b64 from the logs)
# $2 is the encrypted root key (encoded_root_token from the logs)
# $3 is the gpg key of the local unsafe storage (adm.asc from the logs)

decrypt () {
  echo $1 | base64 -d | keybase pgp decrypt
}

vault operator unseal $(decrypt $1)

vault login $(decrypt $2)
vault token create -ttl=2h

echo "copy this token in the setting \"provision_token:\""
echo "and set unsafe_downgrade: true"
echo "then restart the addon, press enter when done"

read a

echo "$3" | base64 -d >> pb2
vault operator unseal $(decrypt $1)

echo "Sleep for elections"
sleep 15 

nonce=$(vault operator rekey -format json -pgp-keys=pb2 -key-shares=1 -key-threshold=1 -init -backup | jq -r .nonce)
vault operator rekey -nonce $nonce $(decrypt $1)
```




