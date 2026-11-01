# Feed signing key

`keys/netbird-pkgs.pub` is generated once by the repository owner (Task 0):

```sh
usign -G -s /tmp/netbird-pkgs.sec -p keys/netbird-pkgs.pub -c "netbird-pkgs feed signing key"
base64 -w0 /tmp/netbird-pkgs.sec   # store as USIGN_SECRET_KEY_B64 in the release environment
usign -F -p keys/netbird-pkgs.pub  # 16-hex fingerprint; commit the pubkey
```

The public key must be committed before the first release; the publish job fails
early when it is missing.
