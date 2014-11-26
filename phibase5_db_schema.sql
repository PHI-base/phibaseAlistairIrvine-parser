CREATE TABLE interaction (
    id SERIAL PRIMARY KEY,
    phi_base_accession varchar(50),
    curation_date date
);

CREATE TABLE interaction_host_phenotype (
    id SERIAL PRIMARY KEY,
    phenotype varchar(50)    
);

CREATE TABLE interaction_host (
    id SERIAL PRIMARY KEY,
    interaction_id integer REFERENCES interaction,
    ncbi_taxon_id integer,
    interaction_host_phenotype_id integer REFERENCES interaction_host_phenotype,
    first_target_uniprot_accession varchar(50),
    genbank_locus_id varchar(50)
);

CREATE TABLE response_ontology (
    id SERIAL PRIMARY KEY,
    response varchar(50)    
);

CREATE TABLE interaction_host_response (
    interaction_host integer REFERENCES interaction_host,
    response_ontology_id integer REFERENCES response_ontology,
    PRIMARY KEY (interaction_host, response_ontology_id)
);

CREATE TABLE pathogen_gene (
    id SERIAL PRIMARY KEY,
    ncbi_taxon_id varchar(50),
    gene_name varchar(50),
    uniparc_id varchar(50),
    genbank_locus_id varchar(50),
    pathway_ontology_id varchar(50)
);

CREATE TABLE phenotype_of_mutant (
    id SERIAL PRIMARY KEY,
    phenotype varchar(50)
);

CREATE TABLE pathogen_gene_mutant (
    id SERIAL PRIMARY KEY,
    pathogen_gene_id integer REFERENCES pathogen_gene,
    ncbi_taxon_id varchar(50),
    uniprot_accession varchar(50),
    phenotype_of_mutant_id integer REFERENCES phenotype_of_mutant
);

CREATE TABLE interaction_pathogen_gene_mutant (
    interaction_id integer REFERENCES interaction,
    pathogen_gene_mutant_id integer REFERENCES pathogen_gene_mutant,
    PRIMARY KEY (interaction_id, pathogen_gene_mutant_id)
);

CREATE TABLE obsolete_reference (
    id SERIAL PRIMARY KEY,
    phi_base_accession varchar(50),
    obsolete_accession varchar(50)
);

CREATE TABLE interaction_literature (
    interaction_id integer REFERENCES interaction,
    pubmed_id varchar(50),
    PRIMARY KEY (interaction_id, pubmed_id)
);

CREATE TABLE protein_interacting_with_mutant (
    pathogen_gene_mutant_id integer REFERENCES pathogen_gene_mutant,
    uniprot_accession varchar(50),
    PRIMARY KEY (pathogen_gene_mutant_id, uniprot_accession)
);

CREATE TABLE modification_within_mutant (
    pathogen_gene_mutant_id integer REFERENCES pathogen_gene_mutant,
    psi_mod_id integer,
    PRIMARY KEY (pathogen_gene_mutant_id, psi_mod_id)
);

CREATE TABLE go_evidence_code (
    id SERIAL PRIMARY KEY,
    code varchar(50)
);

CREATE TABLE interaction_go_term (
    interaction_id integer REFERENCES interaction,
    go_id varchar(50),
    go_evidence_code_id integer REFERENCES go_evidence_code,
    PRIMARY KEY (interaction_id, go_id)
);

CREATE TABLE interaction_transient_assay (
    interaction_id integer REFERENCES interaction,
    bioassay_ontology_id integer,
    PRIMARY KEY (interaction_id, bioassay_ontology_id)    
);

CREATE TABLE evidence_ontology (
    id SERIAL PRIMARY KEY,
    evidence varchar(50)    
);

CREATE TABLE interaction_experimental_evidence (
    interaction_id integer REFERENCES interaction,
    evidence_ontology_id integer REFERENCES evidence_ontology,
    PRIMARY KEY (interaction_id, evidence_ontology_id)    
);

CREATE TABLE curation_organisation (
    id SERIAL PRIMARY KEY,
    name varchar(50)    
);

CREATE TABLE curator (
    id SERIAL PRIMARY KEY,
    initials varchar(50),
    name varchar(50),
    curation_organisation_id integer REFERENCES curation_organisation
);

CREATE TABLE interaction_curator (
    interaction_id integer REFERENCES interaction,
    curator_id integer REFERENCES curator,
    PRIMARY KEY (interaction_id, curator_id)    
);

CREATE TABLE species_expert (
    ncbi_taxon_id varchar(50),
    curator_id integer REFERENCES curator,
    PRIMARY KEY (ncbi_taxon_id, curator_id)
);

CREATE TABLE interaction_tissue (
    interaction_id integer REFERENCES interaction,
    brenda_tissue_ontology_id integer,
    PRIMARY KEY (interaction_id, brenda_tissue_ontology_id)
);

CREATE TABLE frac (
    id SERIAL PRIMARY KEY,
    frac_code varchar(50),    
    moa_code varchar(50),
    moa_name varchar(100),
    target_code varchar(50),    
    target_site varchar(100),    
    group_name varchar(100),    
    chemical_group varchar(100),
    common_name varchar(100),
    resistance_risk varchar(50),
    comments varchar(1000)
);

CREATE TABLE chemical (
    id SERIAL PRIMARY KEY,
    chebi_id varchar(50),
    cas_registry varchar(50),    
    frac_id integer REFERENCES frac,
    mode_in_planta varchar(50)
);

CREATE TABLE interaction_anti_infective_chemical (
    interaction_id integer REFERENCES interaction,
    chemical_id integer REFERENCES chemical,
    PRIMARY KEY (interaction_id, chemical_id)    
);

CREATE TABLE interaction_inducer_chemical (
    interaction_id integer REFERENCES interaction,
    chemical_id integer REFERENCES chemical,
    PRIMARY KEY (interaction_id, chemical_id)    
);

CREATE TABLE disease_severity (
    id SERIAL PRIMARY KEY,
    severity varchar(50)    
);

CREATE TABLE interaction_disease (
    interaction_id integer REFERENCES interaction,
    disease_id integer,
    disease_severity_id integer REFERENCES disease_severity,
    PRIMARY KEY (interaction_id, disease_id)       
);

CREATE TABLE defect_attribute (
    id SERIAL PRIMARY KEY,
    attribute varchar(50)
);

CREATE TABLE defect_value (
    id SERIAL PRIMARY KEY,
    value varchar(50)
);

CREATE TABLE interaction_defect (
    interaction_id integer REFERENCES interaction,
    defect_attribute_id integer REFERENCES defect_attribute,
    defect_value_id integer REFERENCES defect_value
);

