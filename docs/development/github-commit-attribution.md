# GitHub commit attribution

GitHub associates a commit with an account when the commit's author email is
verified on that account. Check the account's email settings and verify the
address before creating commits that should appear under that account.

Set the email for this repository only with:

```sh
git config --local user.email "your-verified-address@example.com"
```

Check the effective repository setting with:

```sh
git config --local --get user.email
```

The author email is recorded in each new commit. Changing `user.email` affects
future commits; it does not change attribution on commits already created.
Changing published history requires rewriting commit objects and coordinating
with every branch and contributor that depends on them. Do not rewrite or
force-push this repository's published history.
