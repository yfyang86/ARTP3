
rawData.genofiles.setup <- function(formula, null, pathway, family, geno.files, lambda, subset = NULL, options = NULL){
  
  start.time <- date()
  
  validate.lambda.rawData(lambda)
  
  # merge and reset options
  options <- options.setup(options, lambda, NULL)
  
  # encoding the row numbers of phenotype data so that I can extract proper subset of genotype data
  rownames(null) <- paste0('SID-', 1:nrow(null))
  
  # subset of data
  null <- data.subset(null, subset, options)
  
  # load definition of pathway
  pathway <- load.pathway.definition(pathway, options)
  
  # check if all genotype files can be found. Missing files will be given in warning messages
  geno.files <- validate.genofiles(geno.files)
  sf <- map.SNPs.to.genofiles(geno.files, pathway)
  
  # deleted snps and their reason
  deleted.snps <- data.frame(SNP = NULL, reason = NULL, comment = NULL, stringsAsFactors = FALSE)
  deleted.genes <- data.frame(Gene = NULL, reason = NULL, comment = NULL, stringsAsFactors = FALSE)
  exc.snps <- intersect(pathway$SNP, options$excluded.snps)
  exc.snps <- setdiff(exc.snps, options$selected.snps)
  deleted.snps <- update.deleted.snps(deleted.snps, exc.snps, reason = "RM_BY_USER", comment = "")
  pathway <- update.pathway.definition(pathway, exc.snps)
  sf <- update.sf(sf, exc.snps)
  
  # 
  exc.snps <- setdiff(pathway$SNP, sf$SNP)
  deleted.snps <- update.deleted.snps(deleted.snps, exc.snps, reason = "NO_RAW_GENO", comment = "")
  pathway <- update.pathway.definition(pathway, exc.snps)
  sf <- update.sf(sf, exc.snps)
  
  #
  
  ini <- data.parse(formula, null)
  rm(null)
  gc()
  null <- ini$null
  resp.var <- ini$resp.var
  comp.id <- which(complete.cases(null))
  if(length(comp.id) < nrow(null)){
    
    msg <- paste0(nrow(null) - length(comp.id), " samples are excluded due to missing covariates. ", length(comp.id), " samples are used")
    message(msg)
    
    null <- null[comp.id, ]
  }
  
  null <- validate.covar(null, resp.var)
  
  control.id <- which(null[, resp.var] == 0)
  
  uni.chr <- unique(pathway$Chr)
  V <- list()
  score0 <- list()
  raw.geno <- NULL
  name <- NULL
  for(i in 1:length(uni.chr)){
    cid <- which(pathway$Chr == uni.chr[i])
    
    if(length(cid) == 0){
      next
    }
    
    uni.gene <- unique(pathway$Gene[cid])
    raw.geno.chr <- NULL
    for(g in uni.gene){
      gid <- which(pathway$Gene == g)
      
      if(length(gid) == 0){
        next
      }
      
      rs <- pathway$SNP[gid]
      tmp <- sf[sf$SNP %in% rs, ]
      gf <- unique(tmp$file)
      geno <- NULL
      for(f in gf){
        tmp1 <- tmp[tmp$file == f, ]
        ncol <- tmp1$ncol[1]
        cc <- rep('NULL', ncol)
        cc[tmp1$col] <- 'numeric'
        rg <- read.table(f, header = TRUE, as.is = TRUE, colClasses = cc)
        if(is.null(geno)){
          geno <- rg
        }else{
          geno <- cbind(geno, rg)
        }
        rm(rg, tmp1)
        gc()
      }
      rm(tmp)
      gc()
      
      sid <- which(paste0('SID-', 1:nrow(geno)) %in% rownames(null))
      
      # geno <- geno[sid, ]
      # the code above will double the memory consumption
      # use the codes below instead
      # the idea comes from @vc273 at 
      # http://stackoverflow.com/questions/10790204/how-to-delete-a-row-by-reference-in-r-data-table
      
      snps <- colnames(geno)
      setDT(geno)
      tmp <- data.table(V1 = geno[[snps[1]]][sid])
      setnames(tmp, names(tmp), snps[1])
      for(s in snps[-1]){
        tmp[, s := geno[[s]][sid], with = FALSE]
        geno[, s := NULL, with = FALSE]
      }
      gc()
      geno <- tmp
      class(geno) <- "data.frame"
      rm(tmp)
      gc()
      
      # SNP filtering based on options
      filtered.data <- filter.raw.geno(geno, pathway[gid, , drop = FALSE], options, control.id)
      filtered.markers <- filtered.data$deleted.snps
      gc()
      
      # update with valid/available SNPs
      exc.snps <- filtered.markers$SNP
      deleted.snps <- update.deleted.snps(deleted.snps, exc.snps, 
                                          reason = filtered.markers$reason, 
                                          comment = filtered.markers$comment)
      pathway <- update.pathway.definition(pathway, exc.snps)
      sf <- update.sf(sf, exc.snps)
      geno <- update.raw.geno(geno, exc.snps)
      if(is.null(raw.geno.chr)){
        raw.geno.chr <- geno
      }else{
        id <- setdiff(colnames(geno), colnames(raw.geno.chr))
        if(length(id) == 0){
          next
        }
        raw.geno.chr <- data.frame(raw.geno.chr, geno[, id, drop = FALSE])
      }
      rm(geno)
      gc()
    }
    
    cid <- which(pathway$Chr == uni.chr[i])
    
    if(length(cid) == 0){
      next
    }
    
    # SNP filtering based on options
    filtered.data <- filter.raw.geno(raw.geno.chr, pathway[cid, , drop = FALSE], options, control.id)
    filtered.markers <- filtered.data$deleted.snps
    filtered.genes <- filtered.data$deleted.genes
    gc()
    
    # update with valid/available SNPs
    exc.snps <- filtered.markers$SNP
    exc.genes <- filtered.genes$Gene
    deleted.snps <- update.deleted.snps(deleted.snps, exc.snps, 
                                        reason = filtered.markers$reason, 
                                        comment = filtered.markers$comment)
    deleted.genes <- update.deleted.genes(deleted.genes, exc.genes, filtered.genes$reason)
    pathway <- update.pathway.definition(pathway, exc.snps, exc.genes)
    sf <- update.sf(sf, exc.snps)
    raw.geno.chr <- update.raw.geno(raw.geno.chr, exc.snps)
    gc()
    
    # calculate normal covariance and mean
    stat <- generate.normal.statistics(resp.var, null, raw.geno.chr, pathway, family, lambda)
    
    if(options$keep.geno){
      if(is.null(raw.geno)){
        raw.geno <- raw.geno.chr
      }else{
        raw.geno <- data.frame(raw.geno, raw.geno.chr)
      }
    }
    
    rm(raw.geno.chr)
    gc()
    
    V[[i]] <- stat$V[[1]]
    score0[[i]] <- stat$score0[[1]]
    name <- c(name, names(stat$V))
    rm(stat)
    gc()
    
  }
  
  names(V) <- name
  names(score0) <- name
  norm.stat <- list(V = V, score0 = score0)
  
  if(!options$keep.geno){
    rm(raw.geno)
    rm(null)
    gc()
    raw.geno <- NULL
    null <- NULL
  }
  
  # trim the information of deleted SNPs
  deleted.snps <- trim.deleted.snps(deleted.snps, options)
  
  msg <- paste0("Setup completed: ", date())
  if(options$print) message(msg)
  
  end.time <- date()
  setup.timing <- as.integer(difftime(strptime(end.time, "%c"), strptime(start.time, "%c"), units = "secs"))
  
  yx <- create.yx(resp.var, null)
  formula <- create.formula(resp.var, yx)
  
  setup <- list(deleted.snps = deleted.snps, deleted.genes = deleted.genes, 
                options = options, pathway = pathway, norm.stat = norm.stat, 
                formula = formula, yx = yx, raw.geno = raw.geno, 
                setup.timing = setup.timing)
  
  if(options$save.setup){
    msg <- paste0("setup file has been saved at ", options$path.setup)
    message(msg)
    save(setup, file = options$path.setup)
  }
  
  setup
  
}
