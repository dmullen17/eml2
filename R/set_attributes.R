#' set_attributes
#'
#' set_attributes
#' @param attributes a joined table of all attribute metadata
#' @param factors a table with factor code-definition pairs; see details
#' @param col_classes optional, list of R column classes ('ordered', 'numeric', 'factor', 'Date', or 'character', case sensitive)
#' will let the function infer missing 'domain' and 'measurementScale' values for attributes column.
#' Should be in same order as attributeNames in the attributes table, or be a named list with names corresponding to attributeNames
#' in the attributes table.
#' @details The attributes data frame must use only the recognized column
#' headers shown here.  The attributes data frame must contain columns for required metadata.
#' These are:
#'
#' For all data:
#' - attributeName (required, free text field)
#' - attributeDefinition (required, free text field)
#' - measurementScale (required, "nominal", "ordinal", "ratio", "interval", or "dateTime",
#'  case sensitive) but it can be inferred from col_classes.
#' - domain (required, "numericDomain", "textDomain", "enumeratedDomain", or "dateTimeDomain",
#'  case sensitive) but it can be inferred from col_classes.
#'
#' For numeric (ratio or interval) data:
#' - unit (required)
#'
#' For character (textDomain) data:
#' - definition (required)
#'
#' For dateTime data:
#' - formatString (required)
#'
#' For factor data:
#'
#' @return an eml "attributeList" object
#' @export
set_attributes <-
  function(attributes,
           factors = NULL,
           col_classes = NULL) {
    ## convert factors to data.frame because it could be a tibble
    ## or tbl_df
    factors <- as.data.frame(factors)

    ## all as characters please (no stringsAsFactors!)
    attributes[] <- lapply(attributes, as.character)
    factors[]  <- lapply(factors, as.character)
    ##  check attributes data.frame.  must declare required columns: attributeName, (attributeDescription, ....)
    ## infer "domain" & "measurementScale" given optional column classes

    attributes <-
      check_and_complete_attributes(attributes, col_classes)

   # check factors
    if(nrow(factors) != 0){
      check_factors(factors)
    }

    ## Add NA columns if necessary FIXME some of these can be missing if their class isn't represented, but otherwise must be present
    for (x in c(
      "precision",
      "minimum",
      "maximum",
      "unit",
      "numberType",
      "formatString",
      "definition",
      "pattern",
      "source",
      "attributeLabel",
      "storageType",
      "missingValueCode",
      "missingValueCodeExplanation"
    )) {
      attributes <- add_na_column(x, attributes)
    }

    out <- list()
    out$attribute <-
      lapply(1:dim(attributes)[1], function(i)
        set_attribute(attributes[i,], factors = factors))

    as_emld(out)
  }





set_attribute <- function(row, factors = NULL) {
  s <- row[["measurementScale"]]


  if (s %in% c("ratio", "interval")) {
    if (!is_standardUnit(row[["unit"]])) {
      type <- "customUnit"
      warning(
        paste0(
          "unit '",
          row[["unit"]],
          "' is not recognized, using custom unit.
          Please define a custom unit or replace with a
          recognized standard unit (see set_unitList() for details)"
        )
        )
    } else {
      type <- "standardUnit"
    }

    u <- setNames(list(list()), type)
    u[[type]] <- row[["unit"]]
    node <- list(
      unit = u,
      precision = row[["precision"]],
      numericDomain = list(
        numberType = row[["numberType"]],
        bounds = set_BoundsGroup(row)
      )
    )
  }

  if (s %in% c("ordinal", "nominal")) {
    node <- list(nonNumericDomain = list())
    if (row[["domain"]] == "textDomain") {
      n <-  list(definition = row[["definition"]],
                  source = row[["source"]],
                  pattern =  row[["pattern"]])
      node$nonNumericDomain$textDomain <- n
    } else if (row[["domain"]] == "enumeratedDomain") {
      node$nonNumericDomain$enumeratedDomain <-
        set_enumeratedDomain(row, factors)

    }
  }


  if (s %in% c("dateTime")) {
    if (is.na(row[["formatString"]])) {
      warning(paste0("The required formatString is missing for attribute ",
                     row[["attributeName"]]))
    }
    node <- list(
      formatString = row[["formatString"]],
      dateTimePrecision = row[["precision"]],
      dateTimeDomain = list(
        bounds = set_BoundsGroup(row)
      )
    )
  }

  measurementScale <- setNames(list(list()), s)
  measurementScale[[s]] <- node
  missingValueCode <- NULL
  if(!is.na(row[["missingValueCode"]])){
    missingValueCode <- list(
      code = na2empty(row[["missingValueCode"]]),
      codeExplanation = na2empty(row[["missingValueCodeExplanation"]]))
  }
  list(
    attributeName = row[["attributeName"]],
    attributeDefinition = row[["attributeDefinition"]],
    attributeLabel = row[["attributeLabel"]],
    storageType = row[["storageType"]],
    missingValueCode = missingValueCode,
    measurementScale = measurementScale
  )
  }

set_enumeratedDomain <- function(row, factors) {
  name <- row[["attributeName"]]
  df <- factors[factors$attributeName == name, ]

  ListOfcodeDefinition <- lapply(1:dim(df)[1], function(i) {
    list(
        code = df[i, "code"],
        definition = df[i, "definition"])
  })
  list(codeDefinition = ListOfcodeDefinition)

}

set_BoundsGroup <- function(row) {
  if (!is.na(row[["minimum"]]))
    minimum = list(
                  na2empty(row[["minimum"]]),
                  "#exclusive" =  "false")
  else
    minimum <- NULL

  if (!is.na(row[["maximum"]]))
    maximum = list(
                  na2empty(row[["maximum"]]),
                  "#exclusive" = "false")
  else
    maximum <- NULL


   list(minimum = minimum,
        maximum = maximum)
}



infer_domain_scale <-
  function(col_classes,
           attributeName = names(col_classes),
           attributes) {
    if (length(col_classes) != nrow(attributes)) {
      if (is.null(names(col_classes))) {
        stop(
          call. = FALSE,
          "If col_classes is not NULL, it must have as many elements as there are rows in attributes unless they are named."
        )

      }
    }
    if (!is.null(names(col_classes))) {
      if (!(all(names(col_classes) %in% attributeName))) {
        stop(
          call. = FALSE,
          "If col_classes is a named list, it should have names corresponding to attributeName."
        )
      }
    }

    if (!(all(
      col_classes[!is.na(col_classes)] %in% c("numeric", "character", "factor", "Date", "ordered")
    ))) {
      stop(
        call. = FALSE,
        "All non missing col_classes values have to be 'ordered', 'numeric', 'character', 'factor' or 'Date'."
      )
    }
    domain <- col_classes
    measurementScale <- col_classes
    storageType <- col_classes
    domain[col_classes == "numeric"] <- "numericDomain"
    domain[col_classes == "character"] <- "textDomain"
    domain[col_classes %in% c("factor", "ordered")] <-
      "enumeratedDomain"
    domain[col_classes %in% c("Date")] <- "dateTimeDomain"
    # compare domain with domain given in attributes if there is one
    if ("domain" %in% names(attributes)) {
      if (!is.null(names(col_classes))) {
        if (any(domain != attributes$domain[attributes$attributeName == names(col_classes)])) {
          whichNot <-
            names(col_classes)[which(domain != attributes$domain[attributes$attributeName == names(col_classes)])]
          stop(
            call. = FALSE,
            paste0(
              "For the attribute ",
              whichNot,
              " the domain value inferred from col_classes does not agree with the domain value existing in attributes. Check col_classes and the domain column you provided.\n"
            )
          )
        }
      } else{
        if (any(domain != attributes$domain)) {
          whichNot <-
            attributes$attributeName[which(domain != attributes$domain)]
          stop(
            call. = FALSE,
            paste0(
              "For the attribute ",
              whichNot,
              " the domain value inferred from col_classes does not agree with the domain value existing in attributes. Check col_classes and the domain column you provided.\n"
            )
          )

        }
      }
    }

    measurementScale[col_classes == "numeric"] <- "ratio" # !
    measurementScale[col_classes == "character"] <- "nominal"
    measurementScale[col_classes == "ordered"] <- "ordinal"
    measurementScale[col_classes == "factor"] <- "nominal"
    measurementScale[col_classes %in% c("Date")] <- "dateTime"

    # compare measurementScale with measurementScale given in attributes if there is one
    if ("measurementScale" %in% names(attributes)) {
      if (!is.null(names(col_classes))) {
        if (any(measurementScale != attributes$measurementScale[attributes$attributeName == names(col_classes)])) {
          whichNot <-
            names(col_classes)[which(measurementScale != attributes$measurementScale[attributes$attributeName == names(col_classes)])]
          stop(
            call. = FALSE,
            paste0(
              "For the attribute ",
              whichNot,
              " the measurementScale value inferred from col_classes does not agree with the measurementScale value existing in attributes. Check col_classes and the measurementScale column you provided.\n"
            )
          )
        }
      } else{
        if (any(measurementScale != attributes$measurementScale)) {
          whichNot <-
            attributes$attributeName[which(measurementScale != attributes$measurementScale)]
          stop(
            call. = FALSE,
            paste0(
              "For the attribute ",
              whichNot,
              " the measurementScale value inferred from col_classes does not agree with the measurementScale value existing in attributes. Check col_classes and the measurementScale column you provided.\n"
            )
          )

        }
      }
    }


    ## storage type is optional, maybe better not to set this?
    storageType[col_classes == "numeric"] <- "float"
    storageType[col_classes == "character"] <- "string"
    storageType[col_classes %in% c("factor", "ordered")] <- "string"
    storageType[col_classes %in% c("Date")] <- "date"

    # compare storageType with storageType given in attributes if there is one
    if ("storageType" %in% names(attributes)) {
      if (!is.null(names(col_classes))) {
        if (any(storageType != attributes$storageType[attributes$attributeName == names(col_classes)])) {
          whichNot <-
            names(col_classes)[which(storageType != attributes$storageType[attributes$attributeName == names(col_classes)])]
          stop(
            call. = FALSE,
            paste0(
              "For the attribute ",
              whichNot,
              " the storageType value inferred from col_classes does not agree with the storageType value existing in attributes. Check col_classes and the storageType column you provided.\n"
            )
          )
        }
      } else{
        if (any(storageType != attributes$storageType)) {
          whichNot <-
            attributes$attributeName[which(storageType != attributes$storageType)]
          stop(
            call. = FALSE,
            paste0(
              "For the attribute ",
              whichNot,
              " the storageType value inferred from col_classes does not agree with the storageType value existing in attributes. Check col_classes and the storageType column you provided.\n"
            )
          )

        }
      }
    }


    data.frame(
      attributeName = attributeName,
      domain = domain,
      measurementScale = measurementScale,
      storageType = storageType,
      stringsAsFactors = FALSE
    )
  }


add_na_column <- function(column, df) {
  if (!column %in% names(df))
    df[[column]] <- as.character(NA)
  df
}


na2empty <- function(x) {
  if (!is.null(x)) {
    if (is.na(x)) {
      x <- character()
    } else if (is.numeric(x)) {
      x <- as.character(x)
    }
  }
  x
}

check_and_complete_attributes <- function(attributes, col_classes) {
  if (!"attributeName" %in% names(attributes)) {
    stop(call. = FALSE,
         "attributes table must include an 'attributeName' column")
  } else{
    if (any(is.na(attributes$attributeName))) {
      stop(call. = FALSE,
           "The attributeName column must be filled for each attribute.")
    }
  }

  ## infer "domain" & "measurementScale" given optional column classes
  if (!is.null(col_classes))
    attributes <-
      merge(
        attributes,
        infer_domain_scale(col_classes, attributes$attributeName,
                           attributes),
        all = TRUE,
        sort = FALSE
      )

  if (!"attributeDefinition" %in% names(attributes)) {
    stop(call. = FALSE,
         "attributes table must include an 'attributeDefinition' column")
  } else{
    if (any(is.na(attributes$attributeDefinition))) {
      stop(call. = FALSE,
           "The attributeDefinition column must be filled for each attribute.")
    }
  }


  if (!"measurementScale" %in% names(attributes)) {
    stop(
      call. = FALSE,
      "attributes table must include an 'measurementScale' column, or you need to input 'col_classes'."
    )
  } else{
    if (any(is.na(attributes$measurementScale))) {
      stop(call. = FALSE,
           "The measurementScale column must be filled for each attribute.")
    } else{
      if (!(all(
        attributes$measurementScale %in% c("nominal", "ordinal", "ratio",
                                           "interval", "dateTime")
      ))) {
        stop(
          call. = FALSE,
          "measurementScale permitted values are 'nominal', 'ordinal', 'ratio', 'interval', 'dateTime'."
        )
      }
    }
  }


  if (!"domain" %in% names(attributes)) {
    stop(
      call. = FALSE,
      "attributes table must include an 'domain' column, or you need to input 'col_classes'."
    )
  } else{
    if (any(is.na(attributes$domain))) {
      stop(call. = FALSE,
           "The domain column must be filled for each attribute.")
    } else{
      if (!(all(
        attributes$domain %in% c(
          "numericDomain",
          "textDomain",
          "enumeratedDomain",
          "dateTimeDomain"
        )
      ))) {
        stop(
          call. = FALSE,
          "domain permitted values are 'numericDomain', 'textDomain',
          'enumeratedDomain', 'dateTimeDomain'."
        )
      }
    }
  }

  # Check that measurementScale and domain values make valid combinations
  if ("measurementScale" %in% names(attributes) &&
      "domain" %in% names(attributes)) {
    for (i in seq_len(nrow(attributes))) {
      mscale <- attributes[i,"measurementScale"]
      domain <- attributes[i,"domain"]

      if (mscale %in% c("nominal", "ordinal") && !(domain %in% c("enumeratedDomain", "textDomain"))) {
        stop(call. = FALSE,
             paste0("The attribute in row ", i, " has an invalid combination of measurementScale (", mscale, ") and domain (", domain,"). For a measurementScale of '", mscale, "', domain must be either 'enumeratedDomain' or 'textDomain'."))
      } else if (mscale %in% c("interval", "ratio") && domain != "numericDomain") {
        stop(call. = FALSE,
             paste0("The attribute in row ", i, " has an invalid combination of measurementScale (", mscale, ") and domain (", domain,"). For a measurementScale of '", mscale, "', domain must be 'numericDomain'."))
      } else if (mscale == "dateTime" && !is.null(domain) && domain != "dateTimeDomain") {
        stop(call. = FALSE,
             paste0("The attribute in row ", i, " has an invalid combination of measurementScale (", mscale, ") and domain (", domain,"). For a measurementScale of '", mscale, "', domain must be 'dateTimeDomain'."))
      }
    }
  }

  return(attributes)
}

# number of codes by attributeName in factors
count_levels <- function(attributeName, factors){
  factors <- factors[factors$attributeName == attributeName,]
  length(unique(factors$code))
}

# number of lines by attributeName in factors
count_lines <- function(attributeName, factors){
  factors <- factors[factors$attributeName == attributeName,]
  nrow(factors)
}

# check the names of factors
# check that for each attributeName codes are unique
check_factors <- function(factors){

  if(!all(c("attributeName", "code", "definition") %in% names(factors))){
    stop("The factors data.frame should have variables called attributeName, code and definition.",
         call. = FALSE)
  }

  lines_no <- vapply(unique(factors$attributeName), count_lines, factors = factors, 1)
  levels_no <- vapply(unique(factors$attributeName), count_levels, factors = factors, 1)

  forcheck <- data.frame(lines_no = lines_no,
                         levels_no = levels_no,
                         attributeName = unique(factors$attributeName))
  notequal <- forcheck[forcheck$lines_no != forcheck$levels_no, ]
  if(nrow(notequal) != 0){
    stop(paste("There are attributeName(s) in factors with duplicate codes:",
               notequal$attributeName),
         call. = FALSE)
  }
}


#' is_standardUnit
#'
#' @param x name of unit to check
#'
#' @return TRUE if unit is exact match to the id of a unit in the Standard Units Table, FALSE otherwise.
#' @export
#'
#' @examples
#' is_standardUnit("amperePerMeter") # TRUE
#' is_standardUnit("speciesPerSquareMeter") # FALSE
is_standardUnit <- function(x) {
  #standard_unit_list <- read.csv(system.file("units/standard_unit_list.csv", package = "EML"))
  standard_unit_list <- standardUnits$units$id
  (x %in% standard_unit_list)
}
