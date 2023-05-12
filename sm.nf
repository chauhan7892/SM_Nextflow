#!/usr/bin/env nextflow

nextflow.enable.dsl=2


// #############################################################################################

/*

================================================================================================
                                    Nextflow SaturMut
================================================================================================
                           Saturation Mutagenesis Analysis Pipeline
                                Author: Pankaj Kumar Chauhan
                                        NCBS-TIFR
------------------------------------------------------------------------------------------------

*/
import groovy.json.JsonSlurper

def manifest = new JsonSlurper().parseText(new File("${projectDir}/manifest.json").text)
// def manifest = new JsonSlurper().parseText(new File("manifest.json").text)

github_repo = manifest.code.github_repo
github_branch = manifest.code.github_branch
git_dir = manifest.code.git_dir
code_dir = manifest.code.code_dir

// Define output directories
processed_dir = params.processed_dir
result_dir = params.result_dir
sample_id = params.sql_table

// Define a custom parameter to choose the profile

// profile = 'conda' // Set a default value

// Create the processed_dir directory if it does not exist
if (!file(processed_dir).exists()) {
    file(processed_dir).mkdirs()
}

// Create the result_dir directory if it does not exist
if (!file(result_dir).exists()) {
    file(result_dir).mkdirs()
}


// Download custom Python code from GitHub repository
"git clone --branch ${github_branch} ${github_repo} ${git_dir}".execute()


// // Define processes

process PROCESS_READS {
    tag "Process Reads"
    publishDir "${processed_dir}", mode: "copy"

    input:
    path script_path
    val threshold_val
    path sql_db_path
    val sql_table
    path sample_file_path
    
    output:
    path "${sample_id}_low_qual_IDs.txt", emit: discarded_ids
    
    script:
    """
    python3 ${script_path} -c ${threshold_val} -i ${sql_db_path} ${sql_table} ${sample_file_path} -o ${sample_id}_low_qual_IDs.txt
    """
}


process ALIGN_READS {
    tag "Align Reads"
    publishDir "${result_dir}", mode: "copy"

    input:
    path script_path
    val mismatch_val
    val processors_used
    path sql_db_path
    val sql_table
    val batch_size
    path reference_path

    output:
    path "${sample_id}_aligned_ids.txt", emit: aligned_ids

    script:
    """
    python3 ${script_path} -c ${mismatch_val} ${processors_used} -i ${sql_db_path} ${sql_table} ${batch_size} ${reference_path} -o ${sample_id}_aligned_ids.txt
    """
}

process CODON_SEARCH {
    tag "Codon Search"
    publishDir "${result_dir}", mode: "copy"

    input:
    path script_path
    path sql_db_path
    val sql_table
    path reference_path
    path query_path

    output:
    path "${sample_id}_with_codons.txt", emit: codon_found
    path "${sample_id}_codon_missing.txt", emit: codon_missing

    script:
    """
    python3 ${script_path} -i ${sql_db_path} ${sql_table} ${reference_path} ${query_path} -o ${sample_id}_with_codons.txt ${sample_id}_codon_missing.txt
    """
}

process CODON_FREQ {
    tag "Codon Frequency"
    publishDir "${result_dir}", mode: "copy"

    input:
    path script_path
    val batch_size
    path query_path

    output:
    path "${sample_id}_codon_freq.txt", emit: codon_freq

    script:
    """
    python3 ${script_path} -c ${batch_size} -i ${query_path} -o ${sample_id}_codon_freq.txt
    """
}

process AA_PLOT {
    tag "AA Plot"
    publishDir "${result_dir}", mode: "copy"

    input:
    path script_path
    path query_path

    output:
    path "${sample_id}_AA_heatmap.pdf", emit: aa_heatmap
    path "${sample_id}_AA_table.txt", emit: aa_table

    script:
    """
    python3 ${script_path} -i ${query_path} -o ${sample_id}_AA_heatmap.pdf ${sample_id}_AA_table.txt
    """
}

// Define channels
process_script_ch = Channel.fromPath("${code_dir}/Fastq_read_with_Phred_sql.py")
seq_file_ch = Channel.fromPath(params.sample_file)
sql_db_ch = Channel.fromPath(params.sql_db)
align_script_ch = Channel.fromPath("${code_dir}/Run_BW_parallel_sql.py")
ref_file_ch = Channel.fromPath(params.ref_file)
codon_search_script_ch = Channel.fromPath("${code_dir}/Codon_Search_sql.py")
codon_freq_script_ch = Channel.fromPath("${code_dir}/Codon_Freq.py")
aa_plot_script_ch = Channel.fromPath("${code_dir}/Codon_Plot.py")


// Define helper functions
def commandExists(String command) {
    def exitCode = sh(script: "command -v ${command} > /dev/null 2>&1", returnStatus: true)
    exitCode == 0
}

workflow {


    if (params.processes.process_reads) {
        PROCESS_READS ( process_script_ch, params.threshold, sql_db_ch, params.sql_table, seq_file_ch )
    }

    if (params.processes.align_reads) {

        ALIGN_READS   ( align_script_ch, params.mismatch, params.processor, sql_db_ch, params.sql_table, params.batch_size, ref_file_ch )
    }

    if (params.processes.codon_analysis) {

        CODON_SEARCH  ( codon_search_script_ch, sql_db_ch, params.sql_table, ref_file_ch, ALIGN_READS.out )

        CODON_FREQ    ( codon_freq_script_ch, params.batch_size, CODON_SEARCH.out.get(0) )

        AA_PLOT       ( aa_plot_script_ch, CODON_FREQ.out )
    }


println """\
================================================================================================
                                     Nextflow SaturMut
================================================================================================
                           Saturation Mutagenesis Analysis Pipeline
                                Author: Pankaj Kumar Chauhan
                                        NCBS-TIFR
------------------------------------------------------------------------------------------------
"""
.stripIndent()
}
