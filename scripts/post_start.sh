#!/usr/bin/env bash

cd /
wget -O training.sh https://cai-data-bucket.s3.ap-northeast-2.amazonaws.com/command/training.sh && chmod +x training.sh
./training.sh