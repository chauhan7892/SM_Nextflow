#!/usr/bin/env bash -e

export my_pwd="$1"

# Check the OS and package manager
OS=$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')
PM=""
if command -v yum > /dev/null; then
    PM="yum"
elif command -v apt-get > /dev/null; then
    PM="apt-get"
elif command -v dnf > /dev/null; then
    PM="dnf"
else
    echo "Unknown or unsupported Linux distribution. Please install Docker manually."
    exit 1
fi

env_name="saturmut"
env_file="sm_env.yml"
image_name="sm_image"
container_name="sm_docker"
nextflow_config_file="sm_env.config"
nextflow_script="sm.nf"
nextflow_config_tempate="sm_env_template.config"



# Install Conda if it is not already installed 
condaInstall(){
    if ! command -v conda &> /dev/null; then
        echo "Conda not found. Installing Miniconda..."
        # Install Miniconda
        if [[ "$(uname -s)" == "Linux" ]]; then
            curl -o miniconda.sh -sSL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
        fi
        bash miniconda.sh -b -p $HOME/miniconda
        rm miniconda.sh
        export PATH="$HOME/miniconda/bin:$PATH"
        conda init bash
        source ~/.bashrc
    fi
}

# Install Docker if it is not already installed
dockerInstall() {
    if ! command -v docker > /dev/null; then
        echo "Docker not found. Installing Docker..."
        if [[ "$OS" == "ubuntu" ]]; then
            $PM update -y
            $PM install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
            add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
            $PM update -y
            $PM install -y docker-ce docker-ce-cli containerd.io
            sudo usermod -aG docker $USER
        elif [[ "$OS" == "centos" ]]; then
            $PM update -y
            $PM install -y yum-utils device-mapper-persistent-data lvm2
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            $PM install -y docker-ce docker-ce-cli containerd.io
            sudo usermod -aG docker $USER
        elif [[ "$OS" == "fedora" ]]; then
            $PM update -y
            $PM install -y dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            $PM install -y docker-ce docker-ce-cli containerd.io
            sudo usermod -aG docker $USER
        else
            echo "Unknown or unsupported Linux distribution. Please install Docker manually."
            exit 1
        fi
    fi
}

# Install Singularity if it is not already installed
singularityInstall(){
    if ! command -v singularity &> /dev/null; then
        echo "Singularity not found. Installing Singularity..."

        if [[ "$PM" == "apt-get" ]]; then
            curl -o singularity.deb -sSL https://github.com/sylabs/singularity/releases/download/v3.11.3/singularity-ce_3.11.3-focal_amd64.deb
            sudo dpkg -i singularity.deb
            rm singularity.deb
        elif [[ "$PM" == "dnf" ]]; then
            curl -o singularity.rpm -sSL https://github.com/sylabs/singularity/releases/download/v3.11.3/singularity-ce-3.11.3-1.el7.x86_64.rpm
            sudo rpm -i singularity.rpm
            rm singularity.rpm
        elif [[ "$PM" == "yum" ]]; then
            curl -o singularity.rpm -sSL https://github.com/sylabs/singularity/releases/download/v3.11.3/singularity-ce-3.11.3-1.el7.x86_64.rpm
            sudo rpm -i singularity.rpm
            rm singularity.rpm
        else
            echo "Unsupported package manager '$PM'. Please install Singularity manually."
            exit 1
        fi
    fi
}

# Download Nextflow
nextflowDownload() {
    curl -s https://get.nextflow.io | bash 2>.error_nextflow
    check_err=$(head -n 1 .error_nextflow | grep -c "java: command not found")
    if [ "$check_err" -eq 1 ]; then
        echo -e "\n\t\e[31m -- ERROR: Please install Java 1.8 (or later). Requirement for Nextflow --\e[39m\n"
        exit 1
    fi
    rm .error_nextflow
}

# Install Nextflow if it is not already installed
nextflowInstall() {
    # Check Nextflow
    check_next=$(command -v nextflow | wc -l)
    if [ "$check_next" -eq 1 ]; then
        echo -e "\n\t -- Nextflow is installed -- \n"
    elif [ "$check_next" -eq 0 ]; then
        check_next=$(ls -1 | grep -v $nextflow_config_file | grep -c "sm_env")
        if [ "$check_next" -eq 1 ]; then
            echo -e "\n\t -- Nextflow is installed -- \n"
        else
            echo -e -n "\n\t    Do you want to install Nextflow? (y or n): "
            read ans
            case $ans in
                [yY] | [yY][eE][sS])
                    echo -e "\n\t -- Downloading Nextflow ... -- \n"
                    nextflowDownload
                    chmod +x nextflow
                    bash nextflow
                    source ~/.bashrc
                    echo -e "\n\t -- Nextflow is now installed on $my_pwd (local installation) -- \n"
                ;;
                [nN] | [nN][oO])
                    echo -e "\n\n\t\e[31m -- ERROR: Download and Install Nextflow. Then rerun the pre-check  --\e[39m\n"
                    exit 0
                ;;
                *)
                    echo -e "\n\n\t\e[31m -- Yes or No answer not specified. Try again --\e[39m\n"
                    nextflowInstall
                ;;
            esac
        fi
    fi
}

getVar () {
    if [[ -z "$my_pwd" ]]; then
        echo -e "\n\t\e[31m -- ERROR: my_pwd variable is not set. Exiting... --\e[39m\n"
        exit 1
    fi

    local nf_path="$my_pwd/nextflow"
    local config_path=$nextflow_config_file

    printf "\n\t -- INFO to use in SaturMut --\n"
    printf "\t Installation PATH:\t %s\n" "$my_pwd"
    printf "\t NEXTFLOW:\t\t %s\n\n" "$nf_path"

    sed "s|pipe_install|pipe_install=\"$my_pwd\"|" "${config_dir}/${nextflow_config_tempate}" > "$config_path"

    if [[ ! -f "$config_path" ]]; then
        echo -e "\n\t\e[31m -- ERROR: Failed to create $nextflow_config_file file. Exiting... --\e[39m\n"
        exit 1
    fi

    # echo "nextflow=$nf_path" > .varfile.sh
    # echo "my_pwd=$my_pwd" >> .varfile.sh

    # if [[ ! -f .varfile.sh ]]; then
    #     echo -e "\n\t\e[31m -- ERROR: Failed to create .varfile.sh file. Exiting... --\e[39m\n"
    #     exit 1
    # fi
}

condaPipelineSetup() {

    condaInstall
    # Check if the Conda environment already exists
    if conda env list | grep -q "^$env_name"; then
    echo "Conda environment '$env_name' already exists."
    else
    echo "Creating Conda environment '$env_name' using '$env_file'..."
    conda env create -f $env_file
    fi
    nextflowInstall
    echo -e "\n\t -- If no \"ERROR\" was found and all the neccesary dependencies are installed proceed to run SaturMut -- \n"
    getVar
}

dockerPipelineSetup() {

    dockerInstall
    # Check if sm_docker Docker image exists
    if docker image inspect $image_name >/dev/null 2>&1; then
        echo "Docker image $image_name already exists"
    else
        # Check if base Docker image exists
        if docker image inspect continuumio/miniconda3 >/dev/null 2>&1; then
            echo "Docker image continuumio/miniconda3 already exists"
        else
            # Pull Docker image
            echo "Pulling Docker image continuumio/miniconda3"
            docker pull continuumio/miniconda3
        fi

        # Check if container exists and is running
        if docker ps --filter "name=$container_name" --format '{{.Names}}' | grep -q $container_name; then
            echo "Docker container $container_name is already running"
        else
            # Check if container exists
            if docker ps -a --filter "name=$container_name" --format '{{.Names}}' | grep -q $container_name; then
                # Start Docker container
                echo "Starting Docker container $container_name"
                docker start $container_name

                # Check Conda environment
                if docker exec -d $container_name conda env list | grep -q $env_name; then
                    echo "Conda environment $env_name already activated in container $container_name"
                    docker commit $container_name $image_name
                else 
                    docker exec -d $container_name /bin/bash -c "conda env create -f /$PWD/$env_file"
                    docker commit $container_name $image_name
                fi
                    
            else
                # # Create Docker container
                echo "Creating Docker container $container_name"
                docker run -d --name $container_name -v $PWD://$PWD continuumio/miniconda3 tail -f /dev/null
                # Create and activate the Conda environment
                docker exec $container_name /bin/bash -c "conda env create -f /$PWD/$env_file && \
                                                        conda clean -afy && \
                                                        find /opt/conda/ -follow -type f -name '*.a' -delete && \
                                                        find /opt/conda/ -follow -type f -name '*.pyc' -delete && \
                                                        find /opt/conda/ -follow -type f -name '*.js.map' -delete && \
                                                        rm -rf /var/lib/apt/lists/*"

                # Commit the container as a new image
                docker commit $container_name $image_name

            fi
        fi
    fi



    nextflowInstall
    echo -e "\n\t -- If no \"ERROR\" was found and all the neccesary dependencies are installed proceed to run SaturMut -- \n"
    getVar
}


singularityPipelineSetup() {

    singularityInstall


    # Check if Docker image exists
    if docker image inspect $image_name >/dev/null 2>&1; then
        echo "Docker image $image_name already exists"
    else
        # Make Docker image
        echo "Make docker image 'sm_image' using option 2"
    fi

    # Check if Singularity image exists
    if [ ! -f ${image_name}.sif ]; then
        # Build Singularity image from Docker image
        echo "Building Singularity image from Docker image"
        sudo singularity build ${image_name}.sif  docker-daemon://${image_name}:latest
        
    fi
        nextflowInstall
        echo -e "\n\t -- If no \"ERROR\" was found and all the neccesary dependencies are installed proceed to run SaturMut -- \n"
        getVar
}


setDependencies(){
    if [ "$1" -eq "1" ];then
        condaPipelineSetup
    elif [ "$1" -eq "2" ];then
        dockerPipelineSetup
    elif [ "$1" -eq "3" ];then
        singularityPipelineSetup
    fi
}



messageText(){
    echo "
    #########################################################################################
    #                                                                                       #
    #                             SaturMut precheck script                                  #
    #                                                                                       #
    #   Options available:                                                                  #
    #                                                                                       #
    #        1- Install conda (if neccesary) and dependencies                               #
    #                                                                                       #
    #               Runs of SaturMut using conda                                            #
    #                                                                                       #
    #        2- Install docker (if neccesary) and dependencies                              #
    #                                                                                       #
    #               Runs of SaturMut with docker                                            #
    #                                                                                       #
    #        3- Install singularity (if neccesary) and dependencies                         #
    #                                                                                       #
    #               Runs of SaturMut with singularity                                       #
    #                                                                                       #  
    #        4- Exit                                                                        #
    #                                                                                       #
    #########################################################################################
    "
}

messageOption(){
    echo -e -n "\t Which option you want? "
    read ans
    case $ans in
        1 | 2 | 3)
            setDependencies $ans
        ;;
        4)
            echo -e "\n\t -- Exit -- \n"
            exit 0
        ;;
        *)
            echo -e "\n\t\e[31m -- Wrong option. Try again --\e[39m\n"
            messageOption
        ;;
    esac
}


main(){
    if [ "$my_pwd" == "" ] || [ "$my_pwd" == "-h" ] || [ "$my_pwd" == "-help" ] || [ "$my_pwd" == "--help" ];then
        echo -e "\n\t Script for checking the requirements of SaturMut \n"
        echo -e "\t Usage:\n\n\t\t bash sm_env.sh WORK_PATH \n"
        echo -e "\t\t\t WORK_PATH = PATH to download requirements used by SaturMut \n\n\t\t\t Example: /home/bioinf/run/ \n"
        exit 0
    elif [ ! -d "$my_pwd" ];then
        echo -e "\n\t -- Directory "${my_pwd}" is not found -- \n"
        echo -e "\n\t -- Creating "${my_pwd}" -- \n"
        mkdir -p ${my_pwd}
        if [ -d "$my_pwd" ];then
            echo -e "\n\t -- Directory created successfully -- \n"
            main
        else
            echo -e "\n\t -- Please provide a valid PATH to run SaturMut -- \n"
            exit 0
        fi
    elif [ -d "$my_pwd" ];then
        if [ "${my_pwd}" == "." ];then
            my_pwd=$(pwd)
            config_dir=$(pwd)
        elif [ "${my_pwd}" == "$(pwd)" ]; then
            config_dir=$(pwd)
        else
            cd "${my_pwd}" && my_pwd=$(pwd) && cd -
            config_dir=$( dirname "${BASH_SOURCE[0]}" )
            if [ "${config_dir}" == "." ];then
                config_dir=$(pwd)
            else
                cd "${config_dir}" && config_dir=$(pwd)
            fi
        fi
        messageText
        messageOption
    fi
}

main