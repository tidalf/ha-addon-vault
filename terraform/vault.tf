provider "vault" {
}

resource "vault_auth_backend" "userpass" {
  type = "userpass"
}

resource "vault_policy" "super_admin" {
  name = "super-admin"

  policy = <<EOT
path "*" {
capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOT
}
