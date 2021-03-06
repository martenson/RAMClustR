#' rc.feature.normalize.qc
#'
#' extractor for xcms objects in preparation for clustering  
#'
#' @param ramclustObj ramclustObj containing MSdata with optional MSMSdata (MSe, DIA, idMSMS)
#' @param qc.inj.range integer how many injections around each injection are to be scanned for presence of QC samples when using batch.qc normalization?  A good rule of thumb is between 1 and 3 times the typical injection span between QC injections.  i.e. if you inject QC ever 7 samples, set this to between 7 and 21.  smaller values provide more local precision but make normalization sensitive to individual poor outliers (though these are first removed using the boxplot function outlier detection), while wider values provide less local precision in normalization but better stability to individual peak areas.
#' @param batch integer vector with length equal to number of injections in xset or csv file
#' @param order integer vector with length equal to number of injections in xset or csv file
#' @param p.cut numeric when run order correction is applied, only features showing a run order vs signal with a linear p-value (after FDR correction) < p.cut will be adjusted.  also requires r-squared < rsq.cut.
#' @param rsq.cut numeric when run order correction is applied, only features showing a run order vs signal with a linear r-squared > rsq.cut will be adjusted. also requires p values < p.cut.
#' @param qc.tag character vector of length one or two.  If length is two, enter search string and factor name in $phenoData slot (i.e. c("QC", "sample.type"). If length one (i.e. "QC"), will search for this string in the 'sample.names' slot by default.
#' @details This function offers normalization by run order, batch number, and QC sample signal intensity.
#' @details Each input vector should be the same length, and equal to the number of samples in the $MSdata set.
#' @details Input vector order is assumed to be the same as the sample order in the $MSdata set.  
#' @return  ramclustR object with normalized data.   
#'  
#' @references Broeckling CD, Afsar FA, Neumann S, Ben-Hur A, Prenni JE. RAMClust: a novel feature clustering method enables spectral-matching-based annotation for metabolomics data. Anal Chem. 2014 Jul 15;86(14):6812-7. doi: 10.1021/ac501530d.  Epub 2014 Jun 26. PubMed PMID: 24927477.
#' @concept ramclustR
#' @concept RAMClustR
#' @concept metabolomics
#' @concept mass spectrometry
#' @concept clustering
#' @concept feature
#' @concept MSFinder
#' @concept xcms
#' @author Corey Broeckling
#' @export

rc.feature.normalize.qc  <- function(ramclustObj=NULL,
                                   order = NULL,
                                   batch = NULL,
                                   qc.tag = NULL,
                                   output.plot = FALSE,
                                   p.cut = 0.05,
                                   rsq.cut = 0.1
) {
  
  ## CHECKS
  if(is.null(ramclustObj)) {
    stop('existing ramclustObj required as input', '\n', 
         '       see rc.get.xcms.data function for one approach to do so', '\n')
  }
  
  if(is.null(order)) {
    warning("order = NULL; run order correction can not be applied.", '\n',
            "       only batch effect will be corrected.", '\n')
    do.order = FALSE
  } else {
    if(!is.numeric(order)) {
      stop('order must be numeric.', '\n')
    }
    do.order = TRUE
  }
  
  if(is.null(batch)) {
    warning("batch = NULL; data will be treated as single batch experiment", '\n')
    batch <- rep(1, nrow(ramclustObj$MSdata))
  }
  
  if(is.null(qc.tag)) {
    warning("qc.tag = NULL; QC based run order correction can not be applied.", '\n',
            "       An assumption of random run order is required for this to be a valid approach.", '\n')
    qc <- rep(TRUE, nrow(ramclustObj$MSdata))
  }
  
  ## define QC samples in each set
  if(length(qc.tag) == 1) {
    qc <- grepl(qc.tag[1], ramclustObj$phenoData$sample.names)
  } 
  if(length(qc.tag) == 2) {
    qc <- grepl(qc.tag[1], ramclustObj$phenoData[[qc.tag[2]]])
  }
  
  if(!is.logical(qc)) {
    stop("qc must be a logical vector", '\n')
  }
  
  
  if(!all.equal(length(batch), length(qc), length(order), nrow(ramclustObj$MSdata))) {
    stop("all lengths must be identical and are not: ", '\n',
         "  length(batch) = ", length(batch), '\n', 
         "  length(order) = ", length(order), '\n',
         "  length(qc) = ", length(qc), '\n',
         "  number of injections = ", nrow(data1), '\n')
  }
  
  
  data1 <- ramclustObj$MSdata
  data1.orig <- data1
  
  mslev <- 1
  if(!is.null(ramclustObj$MSMSdata)) {
    data2 <- ramclustObj$MSMSdata
    data2.org <- data2
    mslev <- 2
  }
  
  ord.corrected <- rep(FALSE, ncol(data1))
  
  data1.median <- apply(data1, 2, "median", na.rm = TRUE)
  data1.min <- apply(data1, 2, 'min', na.rm = TRUE)
  
  data1.qc <- data1[which(qc),]
  data1.qc.median <- apply(data1.qc, 2, "median", na.rm = TRUE)
  rm(data1.qc)
  nar <- which(is.na(data1.qc.median))
  if(length(nar)>0) {
    data1.qc.median[nar] <- data1.min[nar]
  }
  
  if(mslev == 2) {
    data2.median <- apply(data2, 2, "median", na.rm = TRUE)
    data2.min <- apply(data2, 2, 'min', na.rm = TRUE)
    
    data1.qc <- data1[which(qc),]
    data1.qc.median <- apply(data1.qc, 2, "median", na.rm = TRUE)
    rm(data1.qc)
    nar <- which(is.na(data1.qc.median))
    if(length(nar)>0) {
      data1.qc.median[nar] <- data1.min[nar]
    }
    data2.qc <- data2[which(qc),]
    data2.qc.median <- apply(data2.qc, 2, "median", na.rm = TRUE)
    rm(data2.qc)
    nar <- which(is.na(data2.qc.median))
    if(length(nar)>0) {
      data2.qc.median[nar] <- data2.min[nar]
    }
  }
 
  batches <- unique(batch) 
  
  ## 
  for(i in 1:unique(batch)) {
    ##identify which samples are from batch i
    use <- which((batch == i))
    
    ##identify which are qc samples and from batch i
    use.qc <- which(qc & (batch == i))
    
    ## subset
    data1.batch <- data1[use,]
    data1.qc.batch <- data1[use.qc,]
    
    ## calculate batch median value for qc samples.  
    data1.qc.batch.median <- apply(data1.qc.batch, 2, "median", na.rm = TRUE)
    
    ## if any are NA values, replace with global qc median
    nar <- which(is.na(data1.qc.batch.median))
    if(length(nar)>0) {
      data1.qc.batch.median[nar] <-data1.qc.median[nar]
    }
    
    ## calculate global:batch QC fold change and apply correction
    ## this will bring the median signal intensity to similar scales
    ## across batches.  
    
    # consider only applying correction for features demonstrating
    # significant (anova) batch effect.  
    data1.qc.batch.fc <- data1.qc.batch.median / data1.qc.median
    data1[use,] <- data1.batch/data1.qc.batch.fc
    
    if(do.order) {
      ## re-subset
      data1.batch <- data1[use,]
      data1.qc.batch <- data1[use.qc,]
      data1.qc.batch.median <- apply(
        data1.qc.batch, 2, "median", na.rm = TRUE)
      
      data1.qc.batch.fc <- data1.qc.batch
      for(j in 1:nrow(data1.qc.batch.fc)) {
        data1.qc.batch.fc[j,] <- data1.qc.batch[j,]/data1.qc.batch.median
      }

      x <- order[use.qc]
      y <- data1.qc.batch.fc[,1:ncol(data1.qc.batch.fc)]
      
      
      
      ## only correct those featues with significant trendline
      pval <- sapply(1:ncol(y), FUN = function(z) {
        tryCatch({
          cor.test(x, y[,z])$p.val
        }, error = function(x) {1})
      })
      pval <- p.adjust(pval, method = "fdr")
      
      rsqval <- as.vector(cor(x,y[,1:ncol(y)])^2)
      
      do.ord.correct <- which((pval < p.cut) & (rsqval > rsq.cut))
      
      if(length(do.ord.correct) == 0) next
      
      ## record which features have experienced correction
      ord.corrected[do.ord.correct] <- TRUE
      
      y <- data1.qc.batch.fc[,do.ord.correct, drop = FALSE]
      
      p <- predict(
        object = lm(y~x),
        newdata = data.frame(x = use)
      )
      p <- data1[use,do.ord.correct, drop = FALSE] / p
      
      # z <- 300; plot(x, y[,z]); Sys.sleep(2); plot(x, p[use.qc,z])
      
      data1[use,do.ord.correct] <- p[,1:ncol(p)]
      
    }
    data1[which(data1 < 0, arr.ind = TRUE)] <- 0
    ramclustObj$MSdata <- data1
  }
  
  if(!is.null(ramclustObj$MSMSdata)) {
    for(i in 1:unique(batch)) {
      ##identify which samples are from batch i
      use <- which((batch == i))
      
      ##identify which are qc samples and from batch i
      use.qc <- which(qc & (batch == i))
      
      ## subset
      data2.batch <- data2[use,]
      data2.qc.batch <- data2[use.qc,]
      
      ## calculate batch median value for qc samples.  
      data2.qc.batch.median <- apply(data2.qc.batch, 2, "median", na.rm = TRUE)
      
      ## if any are NA values, replace with global qc median
      nar <- which(is.na(data2.qc.batch.median))
      if(length(nar)>0) {
        data2.qc.batch.median[nar] <-data2.qc.median[nar]
      }
      
      ## calculate global:batch QC fold change and apply correction
      ## this will bring the median signal intensity to similar scales
      ## across batches.  
      data2.qc.batch.fc <- data2.qc.batch.median / data2.qc.median
      data2[use,] <- data2.batch/data2.qc.batch.fc
      
      if(do.order) {
        ## re-subset
        data2.batch <- data2[use,]
        data2.qc.batch <- data2[use.qc,]
        data2.qc.batch.median <- apply(
          data2.qc.batch, 2, "median", na.rm = TRUE)
        
        data2.qc.batch.fc <- data2.qc.batch
        for(j in 1:nrow(data2.qc.batch.fc)) {
          data2.qc.batch.fc[j,] <- data2.qc.batch[j,]/data2.qc.batch.median
        }
        
        x <- order[use.qc]
        y <- data2.qc.batch.fc[,1:ncol(data2.qc.batch.fc)]
        
        ## only correct those featues with significant trendline
        pval <- sapply(1:ncol(y), FUN = function(z) {
          tryCatch({
            cor.test(x, y[,z])$p.val
          }, error = function(x) {1})
        })
        pval <- p.adjust(pval, method = "fdr")
        
        rsqval <- as.vector(cor(x,y[,1:ncol(y)])^2)
        
        do.ord.correct <- which((pval < p.cut) & (rsqval > rsq.cut))
        
        if(length(do.ord.correct) == 0) next
        
        ## record which features have experienced correction
        ord.corrected[do.ord.correct] <- TRUE
        y <- data2.qc.batch.fc[,do.ord.correct, drop = FALSE]
        
        p <- predict(
          object = lm(y~x),
          newdata = data.frame(x = use)
        )
        p <- data1[use,do.ord.correct, drop = FALSE] / p
        
        # z <- 300; plot(x, y[,z]); Sys.sleep(2); plot(x, p[use.qc,z])
        
        data2[use,do.ord.correct] <- p[,1:ncol(p)]
      }
      data2[which(data2 < 0, arr.ind = TRUE)] <- 0
      ramclustObj$MSMSdata <- data2
    }
  }
  
  ramclustObj$history$normalize.batch.qc <- paste0(
    "Features were normalized ",
    if(!is.null(ramclustObj$history$normalize.tic)) {"additionally "}, 
    "by linearly regressing run order versus qc feature intensities to account for instrument signal intensity drift.", 
    " Only features with a regression pvalue less than ", p.cut,
    " and an r-squared greater than ", rsq.cut, " were corrected.", 
    "  Of ", length(ord.corrected), " features, ", length(which(ord.corrected)), 
    if(length(which(ord.corrected)) >1) {" were corrected"} else {" was corrected"},
    " for run order effects", 
    if(length(batches)>1) {
      " in at least one batch.  Batch effects were normalized to median intensity for each feature."
      } else {"."}
  )
  
  
  cat(ramclustObj$history$normalize.batch.qc)
  
  return(ramclustObj)
}

