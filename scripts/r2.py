#!/usr/bin/env python3
"""r2.py -- minimal Cloudflare R2 (S3-compatible) helper: upload + presign.

Reads R2_* from the environment (source ~/.r2_creds first). Needs boto3:
  Debian/Kali:  sudo apt install -y python3-boto3
  or a venv:    python3 -m venv ~/.r2venv && ~/.r2venv/bin/pip install boto3

Usage:
  python3 r2.py put <localfile> [key]        # multipart upload (key defaults to basename)
  python3 r2.py presign <key> [seconds]      # presigned GET URL (max 604800 = 7 days)
"""
import os, sys

try:
    import boto3
    from botocore.config import Config
except ImportError:
    sys.exit("boto3 not installed. `sudo apt install -y python3-boto3` or use a venv (see header).")


def client():
    for k in ("R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET"):
        if not os.environ.get(k):
            sys.exit("missing %s (source ~/.r2_creds first)" % k)
    endpoint = os.environ.get("R2_ENDPOINT") or ("https://%s.r2.cloudflarestorage.com" % os.environ["R2_ACCOUNT_ID"])
    return boto3.client(
        "s3", endpoint_url=endpoint,
        aws_access_key_id=os.environ["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"],
        config=Config(signature_version="s3v4", region_name="auto"),
    )


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd, bucket = sys.argv[1], os.environ["R2_BUCKET"]
    if cmd == "put":
        local = sys.argv[2]
        key = sys.argv[3] if len(sys.argv) > 3 else os.path.basename(local)
        client().upload_file(local, bucket, key)   # boto3 chunks large files automatically
        print("uploaded %s -> s3://%s/%s" % (local, bucket, key))
    elif cmd == "presign":
        key = sys.argv[2]
        exp = int(sys.argv[3]) if len(sys.argv) > 3 else 3600
        exp = min(exp, 604800)   # S3 SigV4 hard cap: 7 days
        print(client().generate_presigned_url("get_object", Params={"Bucket": bucket, "Key": key}, ExpiresIn=exp))
    else:
        sys.exit("unknown command %r (put|presign)" % cmd)


if __name__ == "__main__":
    main()
