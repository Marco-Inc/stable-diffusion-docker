#!/usr/bin/env bash
set -e  # Exit the script if any statement returns a non-true return value

# ---------------------------------------------------------------------------- #
#                          Function Definitions                                #
# ---------------------------------------------------------------------------- #

# Start nginx service
start_nginx() {
    echo "Starting Nginx service..."
    service nginx start
}

# Execute script if exists
execute_script() {
    local script_path=$1
    local script_msg=$2
    if [[ -f ${script_path} ]]; then
        echo "${script_msg}"
        bash ${script_path}
    fi
}

# Setup ssh
setup_ssh() {
    if [[ $PUBLIC_KEY ]]; then
        echo "Setting up SSH..."
        mkdir -p ~/.ssh
        echo -e "${PUBLIC_KEY}\n" >> ~/.ssh/authorized_keys
        chmod 700 -R ~/.ssh

        if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
            ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -q -N ''
        fi

        if [ ! -f /etc/ssh/ssh_host_dsa_key ]; then
            ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key -q -N ''
        fi

        if [ ! -f /etc/ssh/ssh_host_ecdsa_key ]; then
            ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -q -N ''
        fi

        if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
            ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -q -N ''
        fi

        service ssh start

        echo "SSH host keys:"
        cat /etc/ssh/*.pub
    fi
}

# Export env vars
export_env_vars() {
    echo "Exporting environment variables..."
    printenv | grep -E '^RUNPOD_|^PATH=|^_=' | awk -F = '{ print "export " $1 "=\"" $2 "\"" }' >> /etc/rp_environment
    echo 'source /etc/rp_environment' >> ~/.bashrc
}

# Start jupyter lab
start_jupyter() {
    if [[ $JUPYTER_PASSWORD ]]; then
        echo "Starting Jupyter Lab..."
        mkdir -p /workspace && \
        cd / && \
        nohup jupyter lab --allow-root \
          --no-browser \
          --port=8888 \
          --ip=* \
          --FileContentsManager.delete_to_trash=False \
          --ContentsManager.allow_hidden=True \
          --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' \
          --ServerApp.token=${JUPYTER_PASSWORD} \
          --ServerApp.allow_origin=* \
          --ServerApp.preferred_dir=/workspace &> /workspace/logs/jupyter.log &
        echo "Jupyter Lab started"
    fi
}

training() {
    echo "training"
    AWS_ACCESS_KEY_ID=$1
    AWS_SECRET_ACCESS_KEY=$2
    USER_ID=$3
    ALBUM_ID=$4
    S3_BUCKET="cai-data-bucket"
    SOURCE_FOLDER="data/${USER_ID}/${ALBUM_ID}/cropped"
    DESTINATION_FOLDER="/workspace/stable-diffusion-webui/models/Lora/img/25_ssaemi dog"
    echo "${AWS_ACCESS_KEY_ID}"
    echo "${AWS_SECRET_ACCESS_KEY}"
    echo "${USER_ID}"
    echo "${ALBUM_ID}"
    echo "${S3_BUCKET}"
    echo "${SOURCE_FOLDER}"
    echo "${DESTINATION_FOLDER}"

    mkdir -p "${DESTINATION_FOLDER}"
    aws configure set aws_access_key_id "${AWS_ACCESS_KEY_ID}"
    aws configure set aws_secret_access_key "${AWS_SECRET_ACCESS_KEY}"
    aws s3 sync "s3://${S3_BUCKET}/${SOURCE_FOLDER}" "${DESTINATION_FOLDER}"

    mkdir -p /workspace/stable-diffusion-webui/models/Lora/model
    mkdir -p /workspace/stable-diffusion-webui/models/Lora/log

    accelerate launch --num_cpu_threads_per_process=2 "/workspace/kohya_ss/sdxl_train_network.py" --enable_bucket --min_bucket_reso=256 --max_bucket_reso=2048 --pretrained_model_name_or_path="/workspace/stable-diffusion-webui/models/realvisxlV20-jcsla-style.safetensors" --train_data_dir="/workspace/stable-diffusion-webui/models/Lora/img" --resolution="1024,1024" --output_dir="/workspace/stable-diffusion-webui/models/Lora/model" --logging_dir="/workspace/stable-diffusion-webui/models/Lora/log" --network_alpha="1" --save_model_as=safetensors --network_module=networks.lora --text_encoder_lr=0.0004 --unet_lr=0.0004 --network_dim=32 --output_name="ssaemi" --lr_scheduler_num_cycles="8" --no_half_vae --full_fp16 --learning_rate="0.0004" --lr_scheduler="constant" --train_batch_size="1" --save_every_n_epochs="1" --mixed_precision="fp16" --save_precision="fp16" --caption_extension=".txt" --cache_latents --cache_latents_to_disk --optimizer_type="Adafactor" --optimizer_args scale_parameter=False relative_step=False warmup_init=False --max_data_loader_n_workers="0" --bucket_reso_steps=64 --gradient_checkpointing --xformers --bucket_no_upscale --noise_offset=0.0 --lowram
}

generate() {
    echo "generate"
    AWS_ACCESS_KEY_ID=$1
    AWS_SECRET_ACCESS_KEY=$2
    USER_ID=$3
    ALBUM_ID=$4
    git clone https://github.com/Marco-Inc/txt2img txt2img
    pip install -r txt2img/requirements.txt
    python txt2img/main.py "${$AWS_ACCESS_KEY_ID}" "${$AWS_SECRET_ACCESS_KEY}" "${$USER_ID}" "${$ALBUM_ID}"
}

# ---------------------------------------------------------------------------- #
#                               Main Program                                   #
# ---------------------------------------------------------------------------- #

AWS_ACCESS_KEY_ID=$1
AWS_SECRET_ACCESS_KEY=$2
USER_ID=$3
ALBUM_ID=$4
echo "${AWS_ACCESS_KEY_ID}"
echo "${AWS_SECRET_ACCESS_KEY}"
echo "${USER_ID}"
echo "${ALBUM_ID}"

start_nginx

mkdir -p /workspace

execute_script "/pre_start.sh" "Running pre-start script..."

echo "Pod Started"

setup_ssh
start_jupyter
export_env_vars

training "${AWS_ACCESS_KEY_ID}" "${AWS_SECRET_ACCESS_KEY}" "${USER_ID}" "${ALBUM_ID}"

generate "${AWS_ACCESS_KEY_ID}" "${AWS_SECRET_ACCESS_KEY}" "${USER_ID}" "${ALBUM_ID}"