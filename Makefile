USER_ID ?= ${shell id -u}
GROUP_ID ?= ${shell id -g}
USER_NAME ?= ${shell whoami}

PROJECT = dd3d
WORKSPACE = /home/${USER_NAME}/workspace/$(PROJECT)
DOCKER_IMAGE = $(PROJECT):latest
DOCKERFILE ?= Dockerfile
SHMSIZE ?= 444G

DOCKER_OPTS = \
	-it \
	--rm \
	-e DISPLAY=${DISPLAY} \
	-v /data:/data \
	-v /tmp:/tmp \
	-v /tmp/.X11-unix:/tmp/.X11-unix \
	-v /mnt/fsx:/mnt/fsx \
	-v ~/.ssh:/home/${USER_NAME}/.ssh \
	-v ~/.aws:/home/${USER_NAME}/.aws \
	-v ~/.cache:/home/${USER_NAME}/.cache \
	-v ${WORKSPACE}:${WORKSPACE} \
	-w ${WORKSPACE} \
	--shm-size=${SHMSIZE} \
	--ipc=host \
	--network=host \
	--privileged

DOCKER_BUILD_ARGS = \
	--build-arg TZ=America/New_York \
	--build-arg USER_ID=${USER_ID} \
	--build-arg GROUP_ID=${GROUP_ID} \
	--build-arg USER_NAME=${USER_NAME} \
	--build-arg WORKSPACE=$(WORKSPACE) \
	--build-arg AWS_ACCESS_KEY_ID \
	--build-arg AWS_SECRET_ACCESS_KEY \
	--build-arg AWS_DEFAULT_REGION \
	--build-arg WANDB_ENTITY \
	--build-arg WANDB_API_KEY \

NGPUS ?= $(shell nvidia-smi -L | wc -l)
MASTER_ADDR ?= 127.0.0.1
MPI_HOSTS ?= localhost:${NGPUS}
MPI_CMD=mpirun \
		-x LD_LIBRARY_PATH \
		-x PYTHONPATH \
		-x MASTER_ADDR=${MASTER_ADDR} \
		-x NCCL_LL_THRESHOLD=0 \
		-x AWS_ACCESS_KEY_ID \
		-x AWS_SECRET_ACCESS_KEY \
		-x WANDB_ENTITY \
		-x WANDB_API_KEY \
		-np ${NGPUS} \
		-H ${MPI_HOSTS} \
		-x NCCL_SOCKET_IFNAME=^docker0,lo \
		--mca btl_tcp_if_exclude docker0,lo \
		-mca plm_rsh_args 'p 12345' \
		--allow-run-as-root

docker-build:
	docker build \
	$(DOCKER_BUILD_ARGS) \
	-f ./docker/$(DOCKERFILE) \
	-t $(DOCKER_IMAGE) .

docker-dev:
	nvidia-docker run --name $(PROJECT) \
	$(DOCKER_OPTS) \
	-v $(PWD):$(WORKSPACE) \
	$(DOCKER_IMAGE) bash

dist-run:
	nvidia-docker run --name $(PROJECT) --rm \
		-e DISPLAY=${DISPLAY} \
		-v ~/.torch:/root/.torch \
		${DOCKER_OPTS} \
		-v $(PWD):$(WORKSPACE) \
		${DOCKER_IMAGE} \
		${COMMAND}

docker-run: docker-build
	nvidia-docker run --name $(PROJECT) --rm \
		${DOCKER_OPTS} \
		${DOCKER_IMAGE} \
		${COMMAND}

docker-interactive: docker-build
	nvidia-docker run --name ${PROJECT} --rm \
		${DOCKER_OPTS} \
		${DOCKER_IMAGE} \
		/bin/bash

docker-jupyter: docker-build
	nvidia-docker run ${DOCKER_OPTS} --name ${PROJECT}_jupyter ${DOCKER_IMAGE} \
		/bin/bash -c "jupyter notebook --port=8889 --ip=0.0.0.0 --allow-root --no-browser --notebook-dir=${WORKSPACE}"

docker-run-mpi: docker-build
	nvidia-docker run ${DOCKER_OPTS} -v $(PWD)/outputs:$(WORKSPACE)/outputs ${DOCKER_IMAGE} \
		bash -c "${MPI_CMD} ${COMMAND}"

clean:
	find . -name '"*.pyc' | xargs sudo rm -f && \
	find . -name '__pycache__' | xargs sudo rm -rf
