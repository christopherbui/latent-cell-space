#' extract quantile (0.01, 0.25, 0.5, 0.75, and 0.99) of  
#' marker specified by markers_to_plot or all (markers_to_plot=NULL
# in_dir = getwd(),
extract_marker_quantiles_4SDL <- function(select_fcs_files, 
                                  in_dir = NULL,                                  
                                  batch_pattern,
                                  arcsine_transform = TRUE, 
                                  markers_to_plot = NULL){ 
                                  
  if (is.null(in_dir)){
     fcs_files <- select_fcs_files 
  } else {
     fcs_files <- file.path(in_dir,select_fcs_files)  #*****
  }
   
  if (!file.exists(fcs_files[1])){
    stop("incorrect file path, the fcs file does not exist")
  }
  
  if(check(norm_markers) == 0){
    
    o <- capture.output(ff_tmp <- read.FCS(file.path(fcs_files[1])))
    
    if (!is.null(markers_to_plot)){
      
      if(!is.character(markers_to_plot)){
        stop ("markers are not a character vector")
      }
      
      matches <- paste(markers_to_plot, collapse="|")
      
      norm_markers <- grep(matches,
                FlowSOM::GetMarkers(ff_tmp, find_mass_ch(ff_tmp,value = TRUE)), 
                value = TRUE, ignore.case = F)
    } else {
      norm_markers <- find_mass_ch(ff_tmp, value = TRUE)
      norm_markers <- FlowSOM::GetMarkers(ff_tmp, norm_markers)
    }
  }
  
  quantile_values <-  c(0.01, 0.25, 0.5, 0.75, 0.99)
  quantiles <- expand.grid(File = fcs_files,
                           Marker = norm_markers,
                           Quantile = quantile_values,
                           Value = NA)
  quantiles <- cbind(quantiles, "Batch" = stringr::str_match(
    basename(as.character(quantiles$File)), batch_pattern)[,2])

  for (file in fcs_files) {
    print(file)
    
    o <- capture.output(ff <- read.FCS(file))  
    
    if(arcsine_transform == TRUE){
      ff <- flowCore::transform(ff, transformList(grep("Di", colnames(ff), value = TRUE),
                                        arcsinhTransform(a = 0, b = 1/5, c = 0)))
    }
         
    for (marker in names(norm_markers)) {
      quantiles_res <-stats::quantile(exprs(ff)[, marker],
                                quantile_values)
      for (i in seq_along(quantiles_res)) {
        quantiles <- quantiles %>%
          dplyr::mutate(Value = replace(Value, 
                                        File == file & 
                                          Marker == norm_markers[marker] &
                                          Quantile == quantile_values[i],
                                        quantiles_res[i]))
        
      }
    }
  }

  quantiles$Sample <- gsub(pattern = "Norm_", replacement = "", ignore.case = TRUE,
                             x = gsub(pattern = "_CC_gated.fcs|_gated.fcs|_beadNorm.fcs|.FCS|.fcs",
                                  replacement = "", ignore.case = TRUE,
                                  x = basename(as.character(quantiles$File))))

  
  quantiles$Sample <- gsub(pattern = "_CC_gated.fcs|_gated.fcs|_beadNorm.fcs|.FCS|.fcs",
                                  replacement = "", ignore.case = TRUE,
                                  x = basename(as.character(quantiles$File)))
 
  Ftab_out <- reshape(quantiles, idvar = c("File","Marker","Batch","Sample"),
                      timevar = "Quantile", direction = "wide") 

  return(Ftab_out)
}

## add nCellsPerSample
file_quality_check_4SDL <- function(fcs_files, 
                               file_batch_id = NULL, 
                               out_dir = getwd(), 
                               nCellsPerSample = 1000,
                               phenotyping_markers = NULL, 
                               arcsine_transform = TRUE, 
                               sd = 3, 
                               nClus = 10){
                               
  
  if(!dir.exists(out_dir)) dir.create(out_dir)
  
  if (!is.null(file_batch_id)) {
    scores <- list()
    for (batch in unique(file_batch_id)){
      print(batch)
      
      tmp_files <- fcs_files[file_batch_id == batch]
      nCells <- nCellsPerSample*length(tmp_files)
      fsom <- fsom_aof_4SDL(fcs_files = tmp_files, 
                       phenotyping_markers = phenotyping_markers, 
                       nCells = nCells,
                       out_dir = out_dir, 
                       arcsine_transform = arcsine_transform,
                       nClus = nClus,
                       batch = batch)
    
      scores[[batch]] <- aof_scoring_4SDL(fcs_files = tmp_files, 
                                     phenotyping_markers = phenotyping_markers,
                                     fsom = fsom, out_dir = out_dir, batch = batch)
    }
    
  } else {
    tmp_files <- fcs_files
    fsom <- fsom_aof_4SDL(fcs_files = tmp_files, phenotyping_markers = phenotyping_markers, 
                     out_dir = out_dir, arcsine_transform = arcsine_transform, 
                     nClus = nClus,
                     batch = NULL)
    
    scores <- aof_scoring_4SDL(fcs_files = tmp_files, 
                          phenotyping_markers = phenotyping_markers,
                          fsom = fsom, out_dir = out_dir, batch = NULL)
  }
  
  final_score <- file_outlier_detecion(scores = scores, out_dir = out_dir, 
                                       sd = sd)
}


fsom_aof_4SDL <- function(fcs_files, 
                     phenotyping_markers,
                     nCells = length(fcs_files)*10000,
                     xdim = 10,
                     ydim = 10,
                     nClus = 10,
                     out_dir, 
                     batch = NULL,
                     arcsine_transform = TRUE, 
                     seed = 1){
  
  
  if(check(phenotyping_channels) == 0){
    o <- capture.output(ff_tmp <- flowCore::read.FCS(file.path(fcs_files[1])))  #****error in original code
    markers <- FlowSOM::GetMarkers(ff_tmp, colnames(ff_tmp))
    phenotyping_channels <- grep(paste(phenotyping_markers, 
                                       collapse = ("|")), markers, value = TRUE)
  }
  
  if(arcsine_transform  == TRUE){
    trans <- transformList(names(phenotyping_channels), CytoNorm::cytofTransform)
  } else {
    trans <- NULL
  }
  
  fsom <- CytoNorm::prepareFlowSOM(file = fcs_files,
                                   colsToUse = names(phenotyping_channels),
                                   seed = seed, 
                                   nCells = nCells,
                                   transformList = trans,
                                   FlowSOM.params = list(xdim = xdim, 
                                                         ydim = ydim, 
                                                         nClus = nClus, 
                                                         scale = FALSE))
  
  myCol <- c("tomato", "violet", "grey50", "slateblue1", "yellow","turquoise2",
             "yellowgreen", "skyblue", "wheat2","steelblue", "blue2", "navyblue",
             "orange", "violetred", "red4", "springgreen2",  "palegreen4",
             "tan", "tan2", "tan3", "brown", "grey70", "grey30")
  
  if(max(as.numeric(fsom$metaclustering)) > length(myCol)){
    backgroundColors <- NULL
  } else {
    backgroundColors <- myCol
  }
  
  if(!is.null(batch)){
    filename <- paste0(batch, "_FlowSOM_clustering.pdf")
  } else {
    filename <- "FlowSOM_clustering.pdf"
  }
  
  # pdf(file.path(out_dir, filename), width = 14, height = 10)
  fsomPlot <- FlowSOM::PlotStars(fsom = fsom, 
                                 title = "FlowSOM clustering",
                                 backgroundValues = fsom$metaclustering, 
                                 maxNodeSize = 3,
                                 backgroundColors = backgroundColors)
  fsomTsne <- FlowSOM::PlotDimRed(fsom = fsom, plotFile = NULL, seed = seed, cTotal = 20000,  
                                  title = "tSNE visualization of FlowSOM metaclusters")
  
  figure <- ggarrange(fsomPlot, fsomTsne,
                      # labels = c("FlowSOM clustering", "tsne"),
                      ncol = 2, nrow = 1)
  
  ggplot2::ggsave(filename = filename, plot = figure, device = "pdf", path = out_dir,
         width =24, height = 10)
  # dev.off()
  
  return(fsom)
}

aof_scoring_4SDL <- function(fcs_files,
                        phenotyping_markers,
                        fsom,
                        out_dir,
                        batch = NULL){
  
  if(check(phenotyping_channels) == 0){
    
    o <- capture.output(ff_tmp <- read.FCS(file.path(fcs_files[1])))    #***error in original code
    markers <- FlowSOM::GetMarkers(ff_tmp, colnames(ff_tmp))
    phenotyping_channels <- grep(paste(phenotyping_markers, 
                                       collapse = ("|")), markers, value = TRUE)
    
    if(length(grep("Ir", phenotyping_channels)) > 1){
      phenotyping_channels <- phenotyping_channels[-(grep("Ir", 
                                                          phenotyping_channels)[2])]
    }
  }
  
  aof_scores <- matrix(NA,
                       nrow = length(fcs_files), 
                       ncol = length(phenotyping_channels),
                       dimnames = list(fcs_files,  
                                       names(phenotyping_channels)))
  
  for(file in fcs_files){ 
    print(paste("calculating AOF", file))
    File_ID <- which(fcs_files == file)
    idx <- which(fsom$data[,"File"] == File_ID)
    fcs_data <- fsom$data[idx,]
    MC <- fsom$metaclustering[fsom$map$mapping[idx, 1]]
    
    aof_tmp <- cytutils::greedyCytometryAof(fcs_data = fcs_data, 
                                            y = MC, 
                                            channel_names = names(phenotyping_channels),
                                            width = 0.05, 
                                            cofactor = 5, 
                                            verbose = TRUE) 
    aof_scores[file, ] <- aof_tmp$Aof
  }
  
  scaled_aof_score(aof_scores = aof_scores, 
                   out_dir = out_dir,
                   aof_channels = phenotyping_channels, 
                   batch = batch)
}


change_fcs_FIL <- function(fcs_files,
                     out_dir = NULL){

  nFiles <- length(fcs_files)

  input.dir <- dirname(fcs_files[1])
  if (is.null(out_dir)){ 
     out_dir <- file.path(input.dir,"updateFileName")
  }

  if (!dir.exists(out_dir)) { 
     dir.create(out_dir)
  }

  for (i in seq_len(nFiles)) {
    fileName <- basename(fcs_files[i])

    f <- flowCore::read.FCS(fcs_files[i])
    f@description$`$FIL` <- fileName
    flowCore::write.FCS(x = f, 
         filename = file.path(out_dir, fileName), 
         endian = "big")
   }
}
   
#-----------------------------------------------
# using lower thres of Ir191 and 193    
gate_intact_cells_4SDL <- function(flow_frame, 
                              file_name = NULL,
                              hard_cutoff = 4,
                              tinypeak_removal1 = 0.8,
                              tinypeak_removal2 = 0.8,
                              alpha1 = 0.05,
                              alpha2 = 0.1, 
                              arcsine_transform = TRUE, ...){
  
  ff <- flow_frame
  
  if (is.null(file_name)){
    file_name <- ff@description$FIL   #****ff@description$GUID.original
  } else {
    file_name 
  }
  
  if(arcsine_transform == TRUE){
    
    ff_t <- flowCore::transform(ff, 
                                flowCore::transformList(colnames(ff)[grep("Di", colnames(ff))], 
                                                        CytoNorm::cytofTransform))
  } else {
    ff_t <- ff
  }
  
  selection <- matrix(TRUE,
                      nrow = nrow(ff),
                      ncol = 1,
                      dimnames = list(NULL,
                                      c("intact")))
  
  tr <- list()
  for(m in c("Ir193Di", "Ir191Di")){
    
    tr[[m]] <- c(flowDensity::deGate(ff_t, m,
                                     tinypeak.removal = tinypeak_removal1, 
                                     upper = FALSE, use.upper = TRUE,
                                     alpha = alpha1, verbose = F, count.lim = 3), 
                 flowDensity::deGate(ff_t, m,
                                     tinypeak.removal = tinypeak_removal2, 
                                     upper = TRUE, use.upper = TRUE,
                                     alpha = alpha2, verbose = F, count.lim = 3)) 
  }
  tr_thres <- tr 

  # ******only using high_thres if low_thres<2 by LT 3/2/25
  ##for(m in c("Ir193Di", "Ir191Di")){
  ##  if (tr[[m]][1]<0.1 | is.na(tr[[m]][1])){  ###*******if low_thres is so low
  ##       selection[ff_t@exprs[,m] < tr[[m]][2], "intact"] <- FALSE
  ##       tr_thres[[m]][3] <- tr[[m]][2]
  ##  }else{
  ##       selection[ff_t@exprs[,m] < tr[[m]][1], "intact"] <- FALSE
  ##       tr_thres[[m]][3] <- tr[[m]][1]
  ##  }
  ##}
  
  for(m in c("Ir193Di", "Ir191Di")){
     if (tr[[m]][1]<0.1 | is.na(tr[[m]][1])){
        if (tr[[m]][2]>hard_cutoff){
           tr_thres[[m]][3]  <- hard_cutoff
           selection[ff_t@exprs[,m] < tr_thres[[m]][3], "intact"] <- FALSE
        } else {
           tr_thres[[m]][3] <- tr[[m]][2]
           selection[ff_t@exprs[,m] < tr[[m]][2], "intact"] <- FALSE
        }
     }else{
         tr_thres[[m]][3] <- tr[[m]][1]
         selection[ff_t@exprs[,m] < tr[[m]][1], "intact"] <- FALSE
      }
   }

 
  percentage <- (sum(selection)/length(selection))*100
  flowDensity::plotDens(ff_t, c("Ir193Di", "Ir191Di"), 
                        main = paste0(basename(file_name)," ( ", format(round(percentage, 2), 
                                                                        nsmall = 2), "% )"))
  
  abline(h = c(tr_thres[["Ir191Di"]]))
  abline(v = c(tr_thres[["Ir193Di"]]))
  points(ff_t@exprs[!selection[,"intact"], c("Ir193Di", "Ir191Di")], pch = ".")

  tr_thres <- as.data.frame(tr_thres)
  tr_thres$info <- c("low","high","selected")
  fout4thres <- gsub(".fcs","_intact_thres.txt",file_name)
  write.table(tr_thres,fout4thres,sep="\t",quote=F,row.names=F)
 
  ff <- ff[selection[,"intact"], ]
  
  return(ff)
}

# -------------------------------------------------------------------------------
# no Ir191-gating
gate_live_cells_4SDL <- function(flow_frame, 
                            file_name = NULL,
                            viability_channel,
                            tinypeak_removal_viability = 0.8,
                            alpha_viability = 0.1,
                            tinypeak_removal_Iridium = 0.8,
                            alpha_Iridium = 0.05,
                            arcsine_transform = TRUE, ... ){
  
  ff <- flow_frame
  
  if (is.null(file_name)){
    file_name <- ff@description$FIL
  } else {
    file_name 
  }
  
  if(arcsine_transform == TRUE){
    
    ff_t <- flowCore::transform(ff, 
                                transformList(colnames(ff)[grep("Di", colnames(ff))], 
                                              CytoNorm::cytofTransform))
  } else {
    ff_t <- ff
  }
  
  selection <- matrix(TRUE,
                      nrow = nrow(ff),
                      ncol = 1,
                      dimnames = list(NULL,
                                      c("live")))
  
  
  v_ch <- grep(viability_channel, colnames(ff), value = T)
  
  tr <- list()
  ###for(m in c("Ir191Di", v_ch)){
  for(m in v_ch){
     upper = TRUE
     alpha = alpha_viability
     tr[[m]] <- flowDensity::deGate(ff_t, m,
                      tinypeak.removal = tinypeak_removal_viability, 
                            upper = upper, use.upper = TRUE,
                            alpha = alpha, verbose = F, count.lim = 3)
  }
  
  # live = x > viability_hi_thres 
  for(m in v_ch){
    selection[ff_t@exprs[,m] > tr[[m]][1], "live"] <- FALSE    
  }
  percentage <- (sum(selection)/length(selection))*100
  flowDensity::plotDens(ff_t, c(v_ch, "Ir191Di"), 
                        main = paste0(file_name," ( ", format(round(percentage, 2), nsmall = 2), "% )"),
                        xlim = c(0, 8), ylim = c(0, 8), ...)
  
  abline(h = tr[["Ir191Di"]])
  abline(v = tr[[v_ch]])
  
  points(ff_t@exprs[!selection[,"live"], c(v_ch, "Ir191Di")], pch = ".") 
  
  ff <- ff[selection[,"live"], ]
  
  return(ff)
  
}





