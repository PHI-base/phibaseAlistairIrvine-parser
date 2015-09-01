#!/usr/bin/perl
use strict;
use warnings;
use DBI; # load perl postgresql module
use LWP::Simple;
use JSON;
use XML::Twig;

# load PHI-base functions
use phibase_subroutines 
  qw(connect_to_phibase 
     query_uniprot 
     ontology_mapping
    );

my $db_conn = connect_to_phibase(); # connect to PHI-base database

# open output file for tab-separated data
my $db_data_filename = '../output/all_database_data.tsv';  
open (DATABASE_DATA_FILE, "> $db_data_filename") or die "Error opening output file\n";

# open output file for JSON encoded data
my $json_data_filename = '../output/all_database_data.json';  
open (JSON_DATA_FILE, "> $json_data_filename") or die "Error opening output file\n";

# create hash for JSON output
# and assign an empty array of interactions to the hash
my %json_output = ();
my @interactions = ();
$json_output{"interactions"} = \@interactions;

# print the headers for the output file
print DATABASE_DATA_FILE 
"New PHI-base Acc\tOld PHI-base Acc\tUniProt Acc\tGene Name (PHI-base)\tGene Names (UniProt)\tProtein Names (UniProt)\tEMBL Accessions (UniProt)\tPathogen Interacting Proteins\tPathogen Taxon\tDisease\tHost Taxon\tHost Target Protein\tCotyledons\tTissue\tGO Annotations (UniProt)\tGO Annotations (PHI-base)\tPhenotype Outcome\tDefects\tInducers\tInducer CAS IDs\tInducer ChEBI IDs\tAnti-Infectives\tAnti-Infective CAS IDs\tAnti-Infective ChEBI IDs\tFRAC Codes\tFRAC Mode of Action\tFRAC Target Site\tFRAC Group\tFRAC Chemical Group\tFRAC Common Name\tFRAC Resistance Risk\tFRAC Comment\tHost Response\tExperiment Specifications\tCurators\tApprover\tSpecies Experts\tPubMed IDs\tCuration Date\n";

# first, get details of all interactions from the interaction table
my $sql_stmt = qq(SELECT id,phi_base_accession,curation_date FROM interaction);

my $sql_result = $db_conn->prepare($sql_stmt);
$sql_result->execute() or die $DBI::errstr;

my $interaction_count = 0;

# Read in the relevant ontologies
print "Reading ontology files...\n";
my $obo_parser = OBO::Parser::OBOParser->new;
my $exp_spec_ontology = $obo_parser->work("../ontology/phibase/experiment_specification.obo");
my $phen_outcome_ontology = $obo_parser->work("../ontology/phibase/phenotype_outcome.obo");
my $host_response_ontology = $obo_parser->work("../ontology/phibase/host_response.obo");
my $human_disease_ontology = $obo_parser->work("../ontology/Disease/HumanDisease/doid.obo");
my $plant_disease_ontology = $obo_parser->work("../ontology/Disease/PlantDisease/plant_disease_ontology.obo");
my $brenda_tissue_ontology = $obo_parser->work("../ontology/Tissue/BrendaTissueOBO.obo");

print "Parsing PHI-base data...\n";

# iterate through all interactions,
# getting all of the details associated with each one,
# and outputing in both tab-separated format and JSON format
while (my @row = $sql_result->fetchrow_array()) {

  # increment interaction counter
  $interaction_count++;

  # create a new interaction hash to store 
  # details of each interaction for JSON output 
  my %interaction_hash = ();

  # retrieve data from current row of SQL result
  my $interaction_id = shift @row;
  my $phibase_accession = shift @row;
  my $curation_date = shift @row;

  # output PHI-base accession to file and hash
  print DATABASE_DATA_FILE "$phibase_accession\t";
  $interaction_hash{"phibase_accession"} = $phibase_accession;

  # get the obsolete PHI-base accession(s)
  # (for multiple gene interactions their may be multiple obsolete accessions)
  my $sql_stmt2 = qq(SELECT obsolete_accession FROM obsolete
                       WHERE phi_base_accession = '$phibase_accession';
                    );

  my $sql_result2 = $db_conn->prepare($sql_stmt2);
  $sql_result2->execute() or die $DBI::errstr;

  # initalise output string and array for obsolete PHI-base accessions
  my $obsolete_acc_output_string = "";
  my @obsolete_acc_array;

  # with multiple gene interactions,
  # there may be more than one obsolete accession
  # need to retrieve all of them and construct output string 
  # based on semi-colon delimiter
  # and accession to the array of accessions
  while (my @row2 = $sql_result2->fetchrow_array()) {
    my $obsolete_accession = shift @row2;
    $obsolete_acc_output_string .= "$obsolete_accession;";
    push(@obsolete_acc_array, $obsolete_accession);
  }

  # remove the final semi-colon from end of the string
  $obsolete_acc_output_string =~ s/;$//;
  # print the list of obsolete PHI accessions to file
  # and add array to the interaction hash
  print DATABASE_DATA_FILE "$obsolete_acc_output_string\t";
  if (@obsolete_acc_array) {
    $interaction_hash{"obsolete_accessions"} = \@obsolete_acc_array;
  }

  # get the pathogen gene related fields 
  $sql_stmt2 = qq(SELECT uniprot_accession,
                         gene_name,
                         pathogen_gene.ncbi_taxon_id
                    FROM interaction,
                         interaction_pathogen_gene_mutant, 
                         pathogen_gene_mutant,
                         pathogen_gene
                    WHERE interaction.id = $interaction_id
                      AND interaction.id = interaction_pathogen_gene_mutant.interaction_id
                      AND pathogen_gene_mutant.id = interaction_pathogen_gene_mutant.pathogen_gene_mutant_id
                      AND pathogen_gene.id = pathogen_gene_mutant.pathogen_gene_id
                 ;);

  $sql_result2 = $db_conn->prepare($sql_stmt2);
  $sql_result2->execute() or die $DBI::errstr;

  # declare variable to store field values
  my $uniprot_accessions = "";
  my $phibase_gene_names = "";
  my $uniprot_gene_names = "";
  my $uniprot_protein_names = "";
  my $uniprot_embl_accessions = "";
  my $uniprot_go_annotation = "";
  my $path_taxa = "";
  my $pathogen_interacting_proteins = "";

  # declare arrays for JSON output
  # (taxon ID array required to check if curator is species expert)
  my @path_taxon_id_array;
  my @path_taxon_array;
  my @pathogen_gene_array;

  # since there may be multiple pathogen gene mutants in a single interaction
  # (as in multiple gene interaction), need to retrieve all of them and construct
  # output string based on semi-colon delimiter
  while (my @row2 = $sql_result2->fetchrow_array()) {

     my $uniprot_acc = shift @row2;
     my $phibase_gene_name = shift @row2;
     my $path_taxon_id = shift @row2;

     # create a new pathogen gene hash to store 
     # details of each pathogen gene for JSON output 
     my %pathogen_gene_hash = ();

     # append UniProt accession and PHI-base gene name to lists
     # and add them to the pathogen gene hash
     $uniprot_accessions .= "$uniprot_acc;";
     $phibase_gene_names .= "$phibase_gene_name;";
     $pathogen_gene_hash{"uniprot_acc"} = $uniprot_acc;
     $pathogen_gene_hash{"phibase_gene_name"} = $phibase_gene_name;

     # get corresponding data from UniProt

     # RESTful URL query to get gene names for the current UniProt accession
     my $query = "http://www.uniprot.org/uniprot/?format=tab&query=accession:$uniprot_acc&columns=genes,database(EMBL),protein%20names,go-id,go";

     # execute query and process response
     my $gene_names_response = query_uniprot($query);
     my @gene_names_plus_header = split ("\n",$gene_names_response); # split into header & gene names
     my $uniprot_details_string = $gene_names_plus_header[1]; # the uniprot details is second element, after the header
     my @uniprot_fields = split ("\t",$uniprot_details_string); # split into header & gene names

     my $gene_names_string = $uniprot_fields[0]; # the gene names string is the first element of the uniprot fields
     # add the gene names to the TSV and JSON output
     if (defined $gene_names_string) {
       my @uniprot_gene_name_array;
       my @gene_names = split (" ",$gene_names_string); # split into array of individual gene names
       foreach my $gene_name (@gene_names) {
         $uniprot_gene_names .= "$gene_name;";
         push(@uniprot_gene_name_array, $gene_name);
       }
       $pathogen_gene_hash{"uniprot_gene_names"} = \@uniprot_gene_name_array;
     }

     my $embl_ids_string = $uniprot_fields[1]; # the EMBL IDs string is the second element of the uniprot fields
     # add the EMBL IDs to the TSV and JSON output
     if (defined $embl_ids_string) {
       my @uniprot_embl_acc_array;
       my @embl_ids = split (";",$embl_ids_string); # split into array of individual EMBL IDs, wrich are delimited by semi-colon
       foreach my $embl_id (@embl_ids) 
       {
         $uniprot_embl_accessions .= "$embl_id;";
         push(@uniprot_embl_acc_array, $embl_id);
       }
       $pathogen_gene_hash{"uniprot_embl_accessions"} = \@uniprot_embl_acc_array;
     }

     my $protein_names_string = $uniprot_fields[2]; # the protein names string is the third element of the uniprot fields
     # add the protein names to the TSV and JSON output
     if (defined $protein_names_string) {
       my @uniprot_protein_name_array;
       my @protein_names = split (";",$protein_names_string); # split into array of individual EMBL IDs, wrich are delimited by semi-colon
       foreach my $protein_name (@protein_names) 
       {
         $uniprot_protein_names .= "$protein_name;";
         push(@uniprot_protein_name_array,$protein_name);
       }
       $pathogen_gene_hash{"uniprot_protein_names"} = \@uniprot_protein_name_array;
     }

     my $go_ids_string = $uniprot_fields[3]; # the GO IDs string is the fourth element of the uniprot fields
     my $go_names_string = $uniprot_fields[4]; # the GO names string is the fifth element of the uniprot fields
     # add the gene ontology annotation to the TSV and JSON output
     if (defined $go_ids_string) {
       my @uniprot_go_array;
       my @go_ids = split (";",$go_ids_string); # split into array of individual EMBL IDs, wrich are delimited by semi-colon
       my @go_names = split (";",$go_names_string); # split into array of individual EMBL IDs, wrich are delimited by semi-colon
       foreach my $go_id (@go_ids) 
       {
         my %go_hash;
         my $go_name = shift @go_names;
         $uniprot_go_annotation .= "$go_id:$go_name;";
         $go_hash{"go_id"} = $go_id;
         $go_hash{"go_name"} = $go_name;
         push(@uniprot_go_array,\%go_hash);
       }
       $pathogen_gene_hash{"uniprot_go_annotations"} = \@uniprot_go_array;
     }

     # add the pathogen taxon id to the array,
     # if the taxon id is not already in the list
     # (as will be likely for multiple gene interactions)
     my $path_taxon_already_displayed = 0;
     if (not $path_taxon_id ~~ @path_taxon_id_array ) {
       push(@path_taxon_id_array, $path_taxon_id);
     } else {
       $path_taxon_already_displayed = 1;
     }

     # get the pathogen taxon details from the ENA web service
     $query = "http://www.ebi.ac.uk/ena/data/view/Taxon:$path_taxon_id&display=xml";
     my $xml_response = get $query or die "Error getting $query";

     # use XML twig to parse the XML data
     my $xml_twig = XML::Twig->new();
     $xml_twig->parse($xml_response);

     # parse the XML data to get the relevant pathogen taxon info
     my $path_taxon = $xml_twig->root->first_child('taxon');
     my $path_taxon_name = $path_taxon->{'att'}->{'scientificName'};

     # print the pathogen taxon details, with name if available
     # (if the current taxon has not already been displayed)
     # and add the taxon details to the relevant array for JSON output
     if (not $path_taxon_already_displayed) {
       if (defined $path_taxon_name) {
	   $path_taxa .= "$path_taxon_id:$path_taxon_name;";
           my %path_taxon;
           $path_taxon{"pathogen_taxon_id"} = $path_taxon_id;
           $path_taxon{"pathogen_taxon_name"} = $path_taxon_name;
           push (@path_taxon_array, \%path_taxon);
       } else { # just print id
	   $path_taxa .= "$path_taxon_id;";
       }
     }

     # add the current pathogen gene to the array of all pathogen genes
     # (there will be multiple genes for a multiple gene interaction)
     push(@pathogen_gene_array,\%pathogen_gene_hash);

  } # end while pathogen_gene_mutant records

  # add all of the gene data taxon data to the interaction_hash for JSON output
  if (@pathogen_gene_array) {
    $interaction_hash{"pathogen_genes"} = \@pathogen_gene_array;
  }
  if (@path_taxon_array) {
    $interaction_hash{"pathogen_taxa"} = \@path_taxon_array;
  }

  # get the interacting protein uniprot accessions
  # Note that the pathogen interacting protein is not directly connnected
  # to a pathogen gene, since the interacting protein may be the result
  # of a multiple gene interaction (thus is not associated with a single gene)
  my $sql_stmt3 = qq(SELECT uniprot_accession
                    FROM interaction,
                         pathogen_interacting_protein
                   WHERE interaction.id = $interaction_id
                     AND interaction.id = pathogen_interacting_protein.interaction_id
                 ;);

  my $sql_result3 = $db_conn->prepare($sql_stmt3);
  $sql_result3->execute() or die $DBI::errstr;

  # since there may be multiple interacting proteins,
  # need to retrieve all of them and construct output string 
  # based on comma and semi-colon delimiters
  # and add the interacting proteins to the array for JSON output
  my @pathogen_interacting_protein_array;
  while (my @row3 = $sql_result3->fetchrow_array()) {
    my $interacting_protein_uniprot_acc = shift @row3;
    $pathogen_interacting_proteins .= "$interacting_protein_uniprot_acc;";
    push(@pathogen_interacting_protein_array, $interacting_protein_uniprot_acc);
  }

  # add the list of interacting proteins to the interaction hash for JSON output
  if (@pathogen_interacting_protein_array) {
    $interaction_hash{"pathogen_interacting_proteins"} = \@pathogen_interacting_protein_array;
  }

  # remove the final semi-colon from end of the strings
  $uniprot_accessions =~ s/;$//;
  $phibase_gene_names =~ s/;$//;
  $uniprot_gene_names =~ s/;$//;
  $uniprot_protein_names =~ s/;$//;
  $uniprot_embl_accessions =~ s/;$//;
  $uniprot_go_annotation =~ s/;$//;
  $pathogen_interacting_proteins =~ s/;$//;
  $path_taxa =~ s/;$//;

  # print to the output file
  print DATABASE_DATA_FILE "$uniprot_accessions\t$phibase_gene_names\t$uniprot_gene_names\t$uniprot_protein_names\t$uniprot_embl_accessions\t$pathogen_interacting_proteins\t$path_taxa\t";


  # get the disease related fields 
  $sql_stmt2 = qq(SELECT disease_id
                    FROM interaction,
                         interaction_disease
                   WHERE interaction.id = $interaction_id
                     AND interaction.id = interaction_disease.interaction_id
                 ;);

  $sql_result2 = $db_conn->prepare($sql_stmt2);
  $sql_result2->execute() or die $DBI::errstr;
  my @row2 = $sql_result2->fetchrow_array();

  my $disease_id = shift @row2;

  # since this field is not mandatory
  # need to check if a disease exists
  if (defined $disease_id) {

    # use the disease ontologies to retrieve the term name, based on the identifier
    # however, we need to find out which ontology it belongs to (human disease or plant disease)
    my $disease_term;
    my $disease_name;

    # first try to get name from plant disease ontology
    $disease_term = $plant_disease_ontology->get_term_by_id($disease_id);
 
    if (defined $disease_term) {
      # if found, then look up name
      $disease_name = $disease_term->name;
    } else { # if not defined, then look up human disease ontology
      $disease_term = $human_disease_ontology->get_term_by_id($disease_id);
      $disease_name = $disease_term->name;
    }

    # now print the disease id and name 
    print DATABASE_DATA_FILE "$disease_id:$disease_name\t";

    # create a hash of the disease details
    # and add this to the interaction hash for JSON output
    my %disease_hash;
    $disease_hash{"disease_id"} = $disease_id;
    $disease_hash{"disease_name"} = $disease_name;
    $interaction_hash{"disease"} = \%disease_hash;

  } else { # no disease found
    print DATABASE_DATA_FILE "\t";
  }


  # create a hash to store details of the host for JSON output 
  my %host_hash = ();

  # get the host related fields 
  $sql_stmt2 = qq(SELECT interaction_host.id,
                         interaction_host.ncbi_taxon_id,
                         interaction_host.first_target_uniprot_accession
                    FROM interaction,
                         interaction_host
                   WHERE interaction.id = $interaction_id
                     AND interaction.id = interaction_host.interaction_id
                 ;);

  $sql_result2 = $db_conn->prepare($sql_stmt2);
  $sql_result2->execute() or die $DBI::errstr;
  @row2 = $sql_result2->fetchrow_array();

  my $interaction_host_id = shift @row2;
  my $host_taxon_id = shift @row2;
  my $host_taxon_string = $host_taxon_id;
  my $host_target_protein = shift @row2;

  # save host target protein to output
  my $host_target_string;
  if (defined $host_target_protein) {
     $host_target_string = $host_target_protein;
     $host_hash{"host_target_protein"} = $host_target_protein;
  } else {
     $host_target_string = '';
  }

  # get the host taxon details from the ENA web service
  my $query = "http://www.ebi.ac.uk/ena/data/view/Taxon:$host_taxon_id&display=xml";
  my $xml_response = get $query or die "Error getting $query";

  # use XML twig to parse the XML data
  my $xml_twig = XML::Twig->new();
  $xml_twig->parse($xml_response);

  # parse the XML data to get the relevant host taxon info
  my %host_taxon_hash;
  my $host_taxon = $xml_twig->root->first_child('taxon');
  my $host_taxon_name = $host_taxon->{'att'}->{'scientificName'};
  $host_taxon_string .= ":$host_taxon_name"; 
  $host_taxon_hash{"host_taxon_id"} = $host_taxon_id;
  $host_taxon_hash{"host_taxon_sci_name"} = $host_taxon_name;

  # need to check if common name exists for this taxon
  my $host_taxon_common_name;
  if ($host_taxon->{'att'}->{'commonName'}) {
    $host_taxon_common_name = "$host_taxon->{'att'}->{'commonName'}";
    $host_taxon_string .= " ($host_taxon_common_name) "; 
    $host_taxon_hash{"host_taxon_common_name"} = $host_taxon_common_name;
  }

  # add the host taxon details to the host hash for JSON
  $host_hash{"host_taxon"} = \%host_taxon_hash;

  # get all the taxon ids for the lineage of the current taxon
  my @lineage_taxa = $host_taxon->first_child('lineage')->children('taxon');

  # cotyledon output string
  my $cotyledon_output_string;

  # flag indicating if mono or dicot found
  my $mono_dicot_found = 0;

  # check each of the lineage taxon IDs against the taxon IDs for monocot (4447) or dicot (71240)
  # then print the appropriate label for the host taxon
  foreach my $lineage_taxon (@lineage_taxa) {

     my $lineage_taxon_id = $lineage_taxon->{'att'}->{'taxId'};

     if ($lineage_taxon_id eq "4447") {
        #print COTYLEDON_FILE "Monocot\n";
        $cotyledon_output_string = "Monocot";
        $mono_dicot_found = 1;
        last;
     } elsif ($lineage_taxon_id eq "71240") {
        #print COTYLEDON_FILE "Dicot\n";
        $cotyledon_output_string = "Dicot";
        $mono_dicot_found = 1;
        last;
     }

  } # end foreach lineage taxon

  # if neither monocot or dicot found in lineage,
  # then assume the host is not a plant species
  unless ($mono_dicot_found) {
     #print COTYLEDON_FILE "n\\a\n";
     $cotyledon_output_string = "n\\a";
  }

  # print the host taxon details
  print DATABASE_DATA_FILE "$host_taxon_string\t$host_target_string\t$cotyledon_output_string\t";


  # initalise output string and array for tissues
  my $tissue_output_string = "";
  my @host_tissues;

  # get the tissue term identifiers
  $sql_stmt2 = qq(SELECT brenda_tissue_id
                    FROM interaction,
                         interaction_tissue
                   WHERE interaction.id = $interaction_id
                     AND interaction.id = interaction_tissue.interaction_id
                 ;);

  $sql_result2 = $db_conn->prepare($sql_stmt2);
  $sql_result2->execute() or die $DBI::errstr;

  # since there may be multiple tissues,
  # need to retrieve all of them and construct output string 
  # based on comma and semi-colon delimiters
  while (@row2 = $sql_result2->fetchrow_array()) {

    my $tissue_id = shift @row2;

    # create hash for the host tissue
    my %tissue_hash;

    # use the tissue ontology to retrieve the term name, based on the identifier
    my $tissue_name = $brenda_tissue_ontology->get_term_by_id($tissue_id)->name;
    $tissue_output_string .= "$tissue_id:$tissue_name;";
    $tissue_hash{"tissue_id"} = $tissue_id;
    $tissue_hash{"tissue_name"} = $tissue_name;
    
    # add the current tissue to array of tissues
    push(@host_tissues, \%tissue_hash);
 
  }

  # remove the final semi-colon from end of the string
  $tissue_output_string =~ s/;$//;
  # output the tissues
  print DATABASE_DATA_FILE "$tissue_output_string\t";
  # add the array of tissues to the host hash for JSON output
  if (@host_tissues) {
    $host_hash{"host_tissues"} = \@host_tissues;
  }


  # get the PHI-base curated Gene Ontology annotation fields 
  $sql_stmt2 = qq(SELECT go_id,
                         go_evidence_code
                    FROM interaction,
                         interaction_go_annotation
                   WHERE interaction.id = $interaction_id
                     AND interaction.id = interaction_go_annotation.interaction_id
                 ;);

  $sql_result2 = $db_conn->prepare($sql_stmt2);
  $sql_result2->execute() or die $DBI::errstr;

  # initalise output string for GO terms and array for JSON output
  my $go_output_string = "";
  my @phibase_go_annotations;

  # since there may be multiple GO terms,
  # need to retrieve all of them and construct output string 
  # based on comma and semi-colon delimiters
  while (@row2 = $sql_result2->fetchrow_array()) {

    # create a hash for the current go annotation
    my %go_annotation;

    my $go_id = shift @row2;
    my $go_evid_code = shift @row2;
    my $go_term = "";

    # add ID and evidence to the hash
    $go_annotation{"go_id"} = $go_id;
    $go_annotation{"go_evidence_code"} = $go_evid_code;

    # retrieve the name of the GO term, using the Quick REST web service
    my $query = "http://www.ebi.ac.uk/QuickGO/GTerm?id=$go_id&format=oboxml";
    my $xml_response = get $query;

    # use XML twig to parse the XML data
    my $xml_twig = XML::Twig->new();

    if (defined $xml_response) {
       # parse the XML data to get the GO term name
       $xml_twig->parse($xml_response);
       if (defined $xml_twig->root->first_child('term')) {
         $go_term = $xml_twig->root->first_child('term')->field('name');
       }
    } else {
       print STDERR "ERROR: Gene Ontology term not found for $go_id\n";
    }


    if (defined $go_evid_code) {  # GO term with evid code
      $go_output_string .= "$go_id($go_evid_code):$go_term;";
      $go_annotation{"go_term_name"} = $go_term;
    } else {  # GO term without evid code
      $go_output_string .= "$go_id:$go_term;";
    }

    # add the current GO annotation to the list of PHI-base curated GO annotation
    push(@phibase_go_annotations, \%go_annotation);

  }

  # remove the final semi-colon from end of the string
  $go_output_string =~ s/;$//;
  # print the list of GO terms to file
  # first print the known GO terms from UniProt
  # followed by the additional GO terms curated into PHI-base
  print DATABASE_DATA_FILE "$uniprot_go_annotation\t$go_output_string\t";

  # add the phibase GO annotation to the interaction hash
  $interaction_hash{"phibase_go_annotations"} = \@phibase_go_annotations;


  # initalise output string for phenotype outcomes and array for JSON output
  my $phenotype_outcome_string = "";
  my @phenotype_outcomes;

  # get the phenotype outcome term identifiers
  $sql_stmt2 = qq(SELECT phenotype_outcome_id
                    FROM interaction,
                         interaction_phenotype_outcome
                   WHERE interaction.id = $interaction_id
                     AND interaction.id = interaction_phenotype_outcome.interaction_id
                 ;);

  $sql_result2 = $db_conn->prepare($sql_stmt2);
  $sql_result2->execute() or die $DBI::errstr;

  # since there may be multiple phenotype outcomes,
  # need to retrieve all of them and construct output string 
  # based on comma and semi-colon delimiters
  while (@row2 = $sql_result2->fetchrow_array()) {

    # create phenotype hash for JSON output
    my %phenotype_hash;

    my $phenotype_outcome_id = shift @row2;

    # use the phenotype outcome ontology to retrieve the term name, based on the identifier
    my $phenotype_outcome_name = $phen_outcome_ontology->get_term_by_id($phenotype_outcome_id)->name;
    $phenotype_outcome_string .= "$phenotype_outcome_id:$phenotype_outcome_name;";
    $phenotype_hash{"phenotype_outcome_id"} = $phenotype_outcome_id;
    $phenotype_hash{"phenotype_outcome_name"} = $phenotype_outcome_name;

    # add the current phenotype to the list of phenotypes
    push(@phenotype_outcomes, \%phenotype_hash);

  }

  # remove the final semi-colon from end of the string
  $phenotype_outcome_string =~ s/;$//;
  # output the Phenotype Outcomes
  print DATABASE_DATA_FILE "$phenotype_outcome_string\t";
  # add the phenotypes outcomes to the interaction hash for JSON output
  if (@phenotype_outcomes) {
    $interaction_hash{"phenotype_outcomes"} = \@phenotype_outcomes;
  }
 

  # get the Defect fields 
  $sql_stmt2 = qq(SELECT defect_attribute.attribute,
                         defect_value.value
                    FROM interaction,
                         interaction_defect,
                         defect_attribute,
                         defect_value
                   WHERE interaction.id = $interaction_id
                     AND interaction.id = interaction_defect.interaction_id
                     AND defect_attribute.id = interaction_defect.defect_attribute_id
                     AND defect_value.id = interaction_defect.defect_value_id
                 ;);

  $sql_result2 = $db_conn->prepare($sql_stmt2);
  $sql_result2->execute() or die $DBI::errstr;

  # initalise output string and JSON array for defects
  my $defect_output_string = "";
  my @defects;

  # since there may be multiple defects,
  # need to retrieve all of them and construct output string 
  # based on colon and semi-colon delimiters
  while (@row2 = $sql_result2->fetchrow_array()) {

    # create a defect hash for JSON output
    my %defect_hash;

    my $attribute = shift @row2;
    my $value = shift @row2;
    $defect_output_string .= "$attribute:$value;";
    $defect_hash{"defect_attribute"} = $attribute;
    $defect_hash{"defect_value"} = $value;

    # add the current defect to the list of defects
    push(@defects, \%defect_hash);

  }

  # remove the final semi-colon from end of the string
  $defect_output_string =~ s/;$//;
  # print the list of defects to file
  print DATABASE_DATA_FILE "$defect_output_string\t";
  # add the list of defects to the interaction hash for JSON output
  if (@defects) {
    $interaction_hash{"defects"} = \@defects;
  }


  # get the Inducer fields 
  $sql_stmt2 = qq(SELECT chemical.name,
                         cas_registry,
                         chebi_id 
                    FROM interaction,
                         interaction_inducer_chemical,
                         chemical
                   WHERE interaction.id = $interaction_id
                     AND interaction.id = interaction_inducer_chemical.interaction_id
                     AND chemical.id = interaction_inducer_chemical.chemical_id
                 ;);

  $sql_result2 = $db_conn->prepare($sql_stmt2);
  $sql_result2->execute() or die $DBI::errstr;

  # create an array of inducers for JSON output
  my @inducers;

  # initalise output string for Inducer names, CAS IDs, and ChEBI IDs
  my $inducer_output_string = "";
  my $inducer_cas_output_string = "";
  my $inducer_chebi_output_string = "";

  # since there may be multiple inducers,
  # need to retrieve all of them and construct output string 
  # based on semi-colon delimiter
  while (@row2 = $sql_result2->fetchrow_array()) {

    # create hash for the inducer
    my %inducer_hash;

    my $chemical = shift @row2;
    my $cas_registry = shift @row2; 
    my $chebi_id = shift @row2;

    if (defined $chemical) {
      $inducer_output_string .= "$chemical;";
      $inducer_hash{"chemical_name"} = $chemical;
    }
    if (defined $cas_registry) {
      $inducer_cas_output_string .= "$cas_registry;";
      $inducer_hash{"cas_registry_id"} = $cas_registry;
    }
    if (defined $chebi_id ) {
      $inducer_chebi_output_string .= "$chebi_id;";
      $inducer_hash{"chebi_id"} = $chebi_id;
    }

    # add current inducer chemical to the list of inducers
    push(@inducers, \%inducer_hash);

  }

  # remove the final semi-colon from end of the strings
  $inducer_output_string =~ s/;$//;
  $inducer_cas_output_string =~ s/;$//;
  $inducer_chebi_output_string =~ s/;$//;
  # print the list of inducers to file
  print DATABASE_DATA_FILE "$inducer_output_string\t$inducer_cas_output_string\t$inducer_chebi_output_string\t";
  # add the list of inducers to the interaction hash for JSON output
  if (@inducers) {
    $interaction_hash{"inducers"} = \@inducers
  }


  # get the Anti-infective fields 
  $sql_stmt2 = qq(SELECT chemical.name,
                         cas_registry,
                         chebi_id 
                    FROM interaction,
                         interaction_anti_infective_chemical,
                         chemical
                   WHERE interaction.id = $interaction_id
                     AND interaction.id = interaction_anti_infective_chemical.interaction_id
                     AND chemical.id = interaction_anti_infective_chemical.chemical_id
                 ;);

  $sql_result2 = $db_conn->prepare($sql_stmt2);
  $sql_result2->execute() or die $DBI::errstr;

  # initalise output string for anti-infective names, CAS IDs, and ChEBI IDs
  my $anti_infective_output_string = "";
  my $anti_infective_cas_output_string = "";
  my $anti_infective_chebi_output_string = "";

  # create an array of anti-infectives for JSON output
  my @anti_infectives;

  # since there may be multiple anti-infectives,
  # need to retrieve all of them and construct output string 
  # based on semi-colon delimiter
  while (@row2 = $sql_result2->fetchrow_array()) {

    # create hash for the anti_infective
    my %anti_infective_hash;

    my $chemical = shift @row2;
    my $cas_registry = shift @row2; 
    my $chebi_id = shift @row2;

    if (defined $chemical) {
      $anti_infective_output_string .= "$chemical;";
      $anti_infective_hash{"chemical_name"} = $chemical;
    }
    if (defined $cas_registry) {
      $anti_infective_cas_output_string .= "$cas_registry;";
      $anti_infective_hash{"cas_registry_id"} = $cas_registry;
    }
    if (defined $chebi_id ) {
      $anti_infective_chebi_output_string .= "$chebi_id;";
      $anti_infective_hash{"chebi_id"} = $chebi_id;
    }

    # add current anti-infective chemical to the list of anti-infectives
    push(@anti_infectives, \%anti_infective_hash);

  }

  # remove the final semi-colon from end of the strings
  $anti_infective_output_string =~ s/;$//;
  $anti_infective_cas_output_string =~ s/;$//;
  $anti_infective_chebi_output_string =~ s/;$//;
  # print the list of anti-infectives to file
  print DATABASE_DATA_FILE "$anti_infective_output_string\t$anti_infective_cas_output_string\t$anti_infective_chebi_output_string\t";
  # add the list of anti_infectives to the interaction hash for JSON output
  if (@anti_infectives) {
    $interaction_hash{"anti_infectives"} = \@anti_infectives
  }


  # get the FRAC related fields (which are part of the anti-infective data)
  $sql_stmt2 = qq(SELECT frac_code, moa_code, moa_name, target_code, target_site, group_name, 
                         chemical_group, common_name, resistance_risk, comments
                    FROM interaction,
                         interaction_anti_infective_chemical,
                         chemical,
                         frac
                   WHERE interaction.id = $interaction_id
                     AND interaction.id = interaction_anti_infective_chemical.interaction_id
                     AND chemical.id = interaction_anti_infective_chemical.chemical_id
                     AND frac.id = chemical.frac_id
                ;);

  $sql_result2 = $db_conn->prepare($sql_stmt2);
  $sql_result2->execute() or die $DBI::errstr;

  # create FRAC array to hold all FRAC chemicals
  my @frac_array;

  # initalise output string for FRAC codes
  my $frac_code_string = "";
  my $frac_moa_string = "";
  my $frac_target_string = "";
  my $frac_group_string = "";
  my $frac_chem_group_string = "";
  my $frac_common_name_string = "";
  my $frac_resistance_string = "";
  my $frac_comments_string = "";

  # since there may be multiple FRAC codes,
  # need to retrieve all of them and construct output string 
  # based on semi-colon delimiter
  while (@row2 = $sql_result2->fetchrow_array()) {

    # create hash to hold FRAC data
    my %frac_hash;

    my $frac_code = shift @row2;
    my $moa_code = shift @row2;
    my $moa_name = shift @row2;
    my $target_code = shift @row2;
    my $target_site = shift @row2;
    my $group_name = shift @row2;
    my $chemical_group = shift @row2;
    my $common_name = shift @row2;
    my $resistance_risk = shift @row2;
    my $comments = shift @row2;

    if (defined $frac_code) {
      $frac_code_string .= "$frac_code;";
      $frac_hash{"frac_code"} = $frac_code;
    }
    if (defined $moa_code) {
      $frac_moa_string .= "$moa_code:$moa_name;";
      $frac_hash{"frac_moa_code"} = $moa_code;
      $frac_hash{"frac_moa_name"} = $moa_name;
    }
    if (defined $target_code) {
      $frac_target_string .= "$target_code:$target_site;";
      $frac_hash{"frac_target_code"} = $target_code;
      $frac_hash{"frac_target_site"} = $target_site;
    }
    if (defined $group_name) {
      $frac_group_string .= "$group_name;";
      $frac_hash{"frac_group_name"} = $group_name;
    }
    if (defined $chemical_group) {
      $frac_chem_group_string .= "$chemical_group;";
      $frac_hash{"frac_chemical_group"} = $chemical_group;
    }
    if (defined $common_name) {
      $frac_common_name_string .= "$common_name;";
      $frac_hash{"frac_common_name"} = $common_name;
    }
    if (defined $resistance_risk) {
      $frac_resistance_string .= "$resistance_risk;";
      $frac_hash{"frac_resistance_risk"} = $resistance_risk;
    }
    if (defined $comments) {
      $frac_comments_string .= "$comments;";
      $frac_hash{"frac_comments"} = $comments;
    }

    # add the current FRAC chemical to the list of FRAC chemicals for this interaction
    push(@frac_array, \%frac_hash);

  }

  # remove the final semi-colon from end of the strings
  $frac_code_string =~ s/;$//;
  $frac_moa_string =~ s/;$//;
  $frac_target_string =~ s/;$//;
  $frac_group_string =~ s/;$//;
  $frac_chem_group_string =~ s/;$//;
  $frac_common_name_string =~ s/;$//;
  $frac_resistance_string =~ s/;$//;
  $frac_comments_string =~ s/;$//;

  # print the list of FRAC details to file
  print DATABASE_DATA_FILE "$frac_code_string\t$frac_moa_string\t$frac_target_string\t$frac_group_string\t$frac_chem_group_string\t$frac_common_name_string\t$frac_resistance_string\t$frac_comments_string\t";

  # add FRAC data to the interaction hash
  # TODO: possibly add the list of FRAC details to the anti-infective hash instead
  # (since the FRAC details belong to the anti-infective chemical, as a fungicide)
  # (but the SQL code should be moved to inside the anti-infective loop,
  # and searched by the FRAC ID from the anti-infective chemical)
  if (@frac_array) {
    $interaction_hash{"frac_data"} = \@frac_array;
  }


  # get the host responses associated with the host
  # initalise output string for host responses
  # and the host response array for JSON output
  my $host_response_string = "";
  my @host_responses;

  # get the host response term identifiers
  $sql_stmt2 = qq(SELECT host_response_id
                    FROM interaction_host,
                         interaction_host_response
                   WHERE interaction_host.id = $interaction_host_id
                     AND interaction_host.id = interaction_host_response.interaction_host_id
                 ;);

  $sql_result2 = $db_conn->prepare($sql_stmt2);
  $sql_result2->execute() or die $DBI::errstr;

  # since there may be multiple host responses,
  # need to retrieve all of them and construct output string 
  # based on semi-colon delimiter
  while (@row2 = $sql_result2->fetchrow_array()) {

    # create hash for the host response
    my %host_response_hash;

    my $host_response_id = shift @row2;
    $host_response_hash{"host_response_id"} = $host_response_id;

    # use the host response ontology to retrieve the term name, based on the identifier
    my $host_term = $host_response_ontology->get_term_by_id($host_response_id);
    my $host_response_name = "";
    if (defined $host_term) {
      $host_response_name = $host_term->name;
      $host_response_hash{"host_response_name"} = $host_response_name
    }
    $host_response_string .= "$host_response_id:$host_response_name;";
  
    # add the current host response to the array of responses
    push(@host_responses, \%host_response_hash);

  }

  # remove the final semi-colon from end of the string
  $host_response_string =~ s/;$//;
  # print the list of host responses to file,
  print DATABASE_DATA_FILE "$host_response_string\t";
  # add the list of host responses to the host hash for JSON output
  if (@host_responses) {
    $host_hash{"host_responses"} = \@host_responses;
  }

  # add the host hash to the interaction hash for JSON output
  $interaction_hash{"host"} = \%host_hash;


  # get the Experiment Specification fields 
  $sql_stmt2 = qq(SELECT experiment_spec_id
                    FROM interaction,
                         interaction_experiment_spec
                   WHERE interaction.id = $interaction_id
                     AND interaction.id = interaction_experiment_spec.interaction_id
                 ;);

  $sql_result2 = $db_conn->prepare($sql_stmt2);
  $sql_result2->execute() or die $DBI::errstr;

  # initalise output string for exp spec
  # and array of experiments for JSON output
  my $exp_spec_output_string = "";
  my @exp_spec_array;

  # since there may be multiple experiment specifications
  # need to retrieve all of them and construct output string 
  # based on semi-colon delimiter
  while (@row2 = $sql_result2->fetchrow_array()) {

    # create hash for the exp spec for JSON output
    my %exp_spec_hash;

    my $exp_spec_id = shift @row2;
    
    # get the term name from the ontology, based on the identifier
    my $exp_spec_name = $exp_spec_ontology->get_term_by_id($exp_spec_id)->name;

    $exp_spec_output_string .= "$exp_spec_id:$exp_spec_name;";
    $exp_spec_hash{"experimental_spec_id"} = $exp_spec_id;
    $exp_spec_hash{"experimental_spec_name"} = $exp_spec_name;

    # add the current exp spec to the list of exp specs
    push(@exp_spec_array, \%exp_spec_hash);

  }

  # remove the final semi-colon from end of the string
  $exp_spec_output_string =~ s/;$//;
  # print the list of experimental evidence to file
  print DATABASE_DATA_FILE "$exp_spec_output_string\t";
  # add the experiemental spec data to the interaction hash for JSON output
  if (@exp_spec_array) {
    $interaction_hash{"experimental_specs"} = \@exp_spec_array;
  }


  # get the Curator fields 
  $sql_stmt2 = qq(SELECT curator.id,
                         curator.name
                    FROM interaction,
                         interaction_curator,
                         curator
                   WHERE interaction.id = $interaction_id
                     AND interaction.id = interaction_curator.interaction_id
                     AND interaction_curator.curator_id = curator.id
                 ;);

  $sql_result2 = $db_conn->prepare($sql_stmt2);
  $sql_result2->execute() or die $DBI::errstr;

  # initalise output string for both Curators and Species Experts
  # as well as array for JSON output
  my $curator_output_string = "";
  my $species_experts_string = "";
  my @curators;
  my @species_experts;

  # since there may be multiple curators,
  # need to retrieve all of them and construct output string 
  # based on comma and semi-colon delimiters
  while (@row2 = $sql_result2->fetchrow_array()) {

    # create a new hash to store curator data for JSON output
    my %curator_hash;

    my $curator_id = shift @row2;
    my $curator_name = shift @row2;
    $curator_hash{"curator_id"} = $curator_id;
    $curator_hash{"curator_name"} = $curator_name;

    # need to determine if the curator belongs to
    # a known organisation
    my $sql_stmt3 = qq(SELECT curation_organisation.name
                         FROM curator,
                              curation_organisation
                        WHERE curator.id = $curator_id
                          AND curation_organisation.id = curator.curation_organisation_id
                     ;);

    my $sql_result3 = $db_conn->prepare($sql_stmt3);
    $sql_result3->execute() or die $DBI::errstr;
    my @row3 = $sql_result3->fetchrow_array();
    my $organisation = shift @row3;

    if (defined $organisation) {  # curator with organisation
      $curator_output_string .= "$curator_name,$organisation;";
      $curator_hash{"curator_organisation"} = $organisation;
    } else {  # curator without organisation
      $curator_output_string .= "$curator_name;";
    }

    # add the current curator to the list of curators
    push(@curators, \%curator_hash);

    # need to determine if the curator is a species expert
    # based on the taxon ids of the pathogens in this interaction
    foreach my $path_taxon_id (@path_taxon_id_array) {
    
       # create a new hash to store species expert data for JSON output
       my %species_expert_hash;

       my $sql_stmt4 = qq(SELECT curator_id
                            FROM species_expert,
                                 curator
                            WHERE species_expert.curator_id = $curator_id
                            AND species_expert.ncbi_taxon_id = $path_taxon_id
                        ;);

       my $sql_result4 = $db_conn->prepare($sql_stmt4);
       $sql_result4->execute() or die $DBI::errstr;
       my @row4 = $sql_result4->fetchrow_array();
       my $expert_curator_id = shift @row4;

       # if a curator id was returned,
       # then the curator is a species expert
       # so add their name to the experts list
       if (defined $expert_curator_id) {

         $species_experts_string .= "$curator_name;";
         $species_expert_hash{"species_expert_curator_id"} = $expert_curator_id;
         $species_expert_hash{"species_expert_name"} = $curator_name;

         # add the current species expert to the list of experts        
         push(@species_experts, \%species_expert_hash);

       }

    } # end foreach pathogen in interaction

  } # end while curators for the interaction

  # remove the final semi-colon from end of the strings
  $curator_output_string =~ s/;$//;
  # print the list of curators to file
  print DATABASE_DATA_FILE "$curator_output_string\t";
  # add the curator list to the interaction hash
  if (@curators) {
    $interaction_hash{"curators"} = \@curators;
  }


  # get the Approver fields (the approver is a special kind of curator)
  $sql_stmt2 = qq(SELECT curator.id,
                         curator.name
                    FROM interaction,
                         interaction_approver,
                         curator
                   WHERE interaction.id = $interaction_id
                     AND interaction.id = interaction_approver.interaction_id
                     AND interaction_approver.curator_id = curator.id
                 ;);

  $sql_result2 = $db_conn->prepare($sql_stmt2);
  $sql_result2->execute() or die $DBI::errstr;

  # initalise output string for Approvers
  # as well as array for JSON output
  my $approver_output_string = "";
  my @approvers;

  # since there may be multiple approvers,
  # need to retrieve all of them and construct output string 
  # based on comma and semi-colon delimiters
  while (@row2 = $sql_result2->fetchrow_array()) {

    # create a new hash to store approver data for JSON output
    my %approver_hash;

    my $curator_id = shift @row2;
    my $approver_name = shift @row2;
    $approver_hash{"curator_id"} = $curator_id;
    $approver_hash{"approver_name"} = $approver_name;

    # need to determine if the approver belongs to
    # a known organisation
    my $sql_stmt3 = qq(SELECT curation_organisation.name
                         FROM curator,
                              curation_organisation
                        WHERE curator.id = $curator_id
                          AND curation_organisation.id = curator.curation_organisation_id
                     ;);

    my $sql_result3 = $db_conn->prepare($sql_stmt3);
    $sql_result3->execute() or die $DBI::errstr;
    my @row3 = $sql_result3->fetchrow_array();
    my $organisation = shift @row3;

    if (defined $organisation) {  # curator with organisation
      $approver_output_string .= "$approver_name,$organisation;";
      $approver_hash{"approver_organisation"} = $organisation;
    } else {  # curator without organisation
      $approver_output_string .= "$approver_name;";
    }

    # add the current approver to the list of approvers
    push(@approvers, \%approver_hash);

    # need to determine if the approver is a species expert
    # based on the taxon ids of the pathogens in this interaction
    foreach my $path_taxon_id (@path_taxon_id_array) {

       # create a new hash to store species expert data for JSON output
       my %species_expert_hash;

       my $sql_stmt4 = qq(SELECT curator_id
                            FROM species_expert,
                                 curator
                            WHERE species_expert.curator_id = $curator_id
                            AND species_expert.ncbi_taxon_id = $path_taxon_id
                        ;);

       my $sql_result4 = $db_conn->prepare($sql_stmt4);
       $sql_result4->execute() or die $DBI::errstr;
       my @row4 = $sql_result4->fetchrow_array();
       my $expert_curator_id = shift @row4;

       # if a curator id was returned,
       # then the curator is a species expert
       # so add their name to the experts list
       if (defined $expert_curator_id) {

         $species_experts_string .= "$approver_name;";
         $species_expert_hash{"species_expert_curator_id"} = $expert_curator_id;
         $species_expert_hash{"species_expert_name"} = $approver_name;

         # add the current species expert to the list of experts
         push(@species_experts, \%species_expert_hash);

       }

    } # end foreach pathogen in interaction

  } # end while curators for the interaction

  # remove the final semi-colon from end of the strings
  $approver_output_string =~ s/;$//;
  $species_experts_string =~ s/;$//;
  # print the list of approver and species experts to file
  print DATABASE_DATA_FILE "$approver_output_string\t$species_experts_string\t";
  # add the approver and species expert lists to the interaction hash
  if (@approvers) {
    $interaction_hash{"approvers"} = \@approvers;
  }
  if (@species_experts) {
    $interaction_hash{"species_experts"} = \@species_experts;
  }


  # get the literature fields 
  $sql_stmt2 = qq(SELECT interaction_literature.pubmed_id
                    FROM interaction,
                         interaction_literature
                   WHERE interaction.id = $interaction_id
                     AND interaction.id = interaction_literature.interaction_id
                ;);

  $sql_result2 = $db_conn->prepare($sql_stmt2);
  $sql_result2->execute() or die $DBI::errstr;

  # initalise output string and JSON array for literature
  my $pubmed_output_string = "";
  my @pubmed_articles;

  # since there may be multiple PubMed articles,
  # need to retrieve all of them and construct output string 
  # based on semi-colon delimiter
  while (@row2 = $sql_result2->fetchrow_array()) {

    # create pubmed hash for JSON output
    my %pubmed_hash;

    my $pubmed_id = shift @row2;
    $pubmed_hash{"pubmed_id"} = $pubmed_id;

    # run REST query and get JSON response
    my $url = "http://www.ebi.ac.uk/europepmc/webservices/rest/search/query=EXT_ID:$pubmed_id&format=json";
    my $json_response = get $url;
    my $text_response = decode_json($json_response);

    # parse each of the relevant parameters from the JSON text
    my $authors = $text_response->{'resultList'}{'result'}[0]{'authorString'};
    my $year    = $text_response->{'resultList'}{'result'}[0]{'pubYear'};
    my $title   = $text_response->{'resultList'}{'result'}[0]{'title'};
    my $journal = $text_response->{'resultList'}{'result'}[0]{'journalTitle'};
    my $volume  = $text_response->{'resultList'}{'result'}[0]{'journalVolume'};
    my $issue   = $text_response->{'resultList'}{'result'}[0]{'issue'};
    my $pages   = $text_response->{'resultList'}{'result'}[0]{'pageInfo'};
    my $doi     = $text_response->{'resultList'}{'result'}[0]{'doi'};

    # if title is empty or undefined, then assume the article has not been found
    if (defined $title and $title ne "") {

       # print article details in citation format
       # note that warnings about non-ascii characters is suppressed,
       # but these characters may not display as desired.
       { no warnings; $pubmed_output_string .= "$pubmed_id: $authors ($year). \"$title\" $journal $volume($issue): $pages. $doi.;" };

       # add each of the details to the pubmed hash
       $pubmed_hash{"pubmed_authors"} = $authors;
       $pubmed_hash{"pubmed_year"} = $year;
       $pubmed_hash{"pubmed_title"} = $title;
       $pubmed_hash{"pubmed_journal"} = $journal;
       $pubmed_hash{"pubmed_volume"} = $volume;
       $pubmed_hash{"pubmed_issue"} = $issue;
       $pubmed_hash{"pubmed_pages"} = $pages;
       $pubmed_hash{"pubmed_doi"} = $doi;
       
    } else { # article not found
       $pubmed_output_string .= "$pubmed_id: Not Found;";
    }

    # add current pubmed record to the list of pubmed articles for this interaction
    push(@pubmed_articles, \%pubmed_hash);

  } # end while pubmed articles

  # remove the final semi-colon from end of the string
  $pubmed_output_string =~ s/;$//;
  # print the list of pubmed ids to file
  print DATABASE_DATA_FILE "$pubmed_output_string\t";
  # add the list of pubmed ids to the interaction hash for JSON output
  $interaction_hash{"pubmed_articles"} = \@pubmed_articles;

  # finally, output curation date
  print DATABASE_DATA_FILE "$curation_date\n";
  $interaction_hash{"curation_date"} = $curation_date;

  # add the interaction hashref to the array of interactions
  # note the backslash used to deference the hash
  push(@interactions,\%interaction_hash);
 
  # print message for every 50th PHI-base interaction processed
  print "PHI-base annotations processed:$interaction_count\n" unless ($interaction_count % 50);

}

close (DATABASE_DATA_FILE);

$sql_result->finish() or die "Failed to finish SQL statement\n";
$db_conn->disconnect() or die "Failed to disconnect database\n";

# encode JSON output hash into JSON format
# Note that the encode_json requires a hashref, not the hash itself
# so it's prefixed with backslash
my $json_data = encode_json(\%json_output);
open (JSON_DATA_FILE, "> $json_data_filename") or die "Error opening output file\n";
print JSON_DATA_FILE $json_data;
print $json_data."\n";

# test if the JSON output produces proper hash string
#use Data::Dumper;
#my $json_string = decode_json($json_data);
#print Dumper($json_string)."\n";

print "\nProcess completed successfully.\n";
print "Total interactions:$interaction_count\n";
print "Tab-separated file of all PHI-base data: $db_data_filename\n\n";

