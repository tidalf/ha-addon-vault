# Changelog
All notable changes to this project will be documented in this file.

# Unreleased
### Added
- nginx

## [0.3] - 2021-01-02
### Added
- s6 process supervision
- terraform for provisioning
- unsafe auto unseal
- gpg/keybase encryption of init keys for the users
- migrations between modes (hacky)
- gpg encryption of init keys for (less) unsafe auto unseal and migrations (very hacky)

## [0.2] - 2020-12-27
### Added
- setting for node_id
- badges

## [0.1] - 2020-12-27
### Added
- launch vault using available certs
- use tempio to template the config
- config for aws auto unseal 
