*****************************


Date: 2023-05-12 12:04:38.431818
Nextlfow pipeline Saturation_Mutagenesis
Personnel: Pankaj Chauhan
*****************************


 
 
Question: 
Objective: 
Outline: 



## set the git main to github
git remote add -u sm https://github.com/chauhan7892/SM_Nextflow.git


## Set the nextflow dependencies using bash script. It is a comprehensive script taking care of conda/docker/singularity installation, related python dependencies installation and nextflow installation.  
bash sm_env.sh .

#### Nextflow run
# 1 using local conda
nextflow run sm.nf -profile conda -c nf_sm.config

# 2 using docker
nextflow run sm.nf -profile docker -c nf_sm.config

# 3 using singularity
nextflow run sm.nf -profile singularity -c nf_sm.config

