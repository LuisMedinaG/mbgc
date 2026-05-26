# Non-secret backend config for CI. Credentials come from
# TF_BACKEND_ACCESS_KEY / TF_BACKEND_SECRET_KEY GitHub Actions secrets.
bucket    = "mbgc-tfstate"
endpoints = { s3 = "https://mlltpfszhtxhphoaeydh.storage.supabase.co/storage/v1/s3" }
