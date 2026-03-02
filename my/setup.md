

Use a fine-grained token scoped to just this repo:
Go to https://github.com/settings/personal-access-tokens/new
Fill in:
Token name: nanoclaw-gcp
Expiration: No expiration (or 1 year)
Repository access: Only select repositories → pick nanoclaw
Permissions → Contents: Read-only
Click Generate token and copy it
Then on the VM:
git clone https://gaaady:YOUR_TOKEN@github.com/gaaady/nanoclaw.gitcd nanoclawnpm installnpm run build