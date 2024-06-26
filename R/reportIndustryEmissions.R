#' Read in GDX and calculate industry emissions, used in convGDX2MIF.R for the reporting
#'
#' Read in emissions data from GDX file, information used in convGDX2MIF.R
#' for the reporting
#'
#'
#' @param gdx a GDX object as created by readGDX, or the path to a gdx
#' @param output a magpie object containing all needed variables generated by other report*.R functions
#' @return MAgPIE object - contains the emission variables
#' @author Sebastian Osorio
#' @seealso \code{\link{convGDX2MIF}}
#' @examples
#'
#' \dontrun{reportIndustryEmissions(gdx,output=NULL)}
#'
#' @importFrom gdx readGDX
#' @importFrom magclass mbind setNames dimSums getSets getSets<- as.magpie
#' @export
#'
reportIndustryEmissions <- function(gdx,output=NULL) {

  if(is.null(output)){
    stop("please provide a file containing all needed information")
  }

  # read switch for EU ETS
  #banking constraint... many of the variables should not be reported if EU ETS is not modelled at least partially
  c_bankemi_EU <- readGDX(gdx,name="c_bankemi_EU",field="l",format="first_found")

  if(c_bankemi_EU == 1) {

    #Read LIMES version (industry was included in version 2.27)
    c_LIMESversion <- readGDX(gdx,name="c_LIMESversion",field="l",format="first_found")

    tmp <- NULL

    if(c_LIMESversion > 2.26) {

      c_industry_ETS <- readGDX(gdx,name="c_industry_ETS",field="l",format="first_found")

      #Only estimate the industry-related variables if this is modelled
      if(c_industry_ETS == 1) {
        #read variables
        v_ind_emiabatproc <- readGDX(gdx,name="v_ind_emiabatproc",field="l",format="first_found")
        y <- getYears(v_ind_emiabatproc)

        # read parameters
        s_c2co2 <- readGDX(gdx,name="s_c2co2",field="l",format="first_found") #conversion factor C -> CO2
        p_ind_emiabat <- readGDX(gdx,name="p_ind_emiabat",field="l",format="first_found")
        p_ind_emimac <- readGDX(gdx,name="p_ind_emimac",field="l",format="first_found")

        # reduce to years actually used (t in the model)
        p_ind_emiabat <- p_ind_emiabat[, y, ]
        p_ind_emimac <- p_ind_emimac[, y, ]

        # create MagPie object of variables with iso3 regions
        p_ind_emiabat <- limesMapping(p_ind_emiabat)
        v_ind_emiabatproc <- limesMapping(v_ind_emiabatproc)
        p_ind_emimac <- limesMapping(p_ind_emimac)

        #Estimate industry emissions (baselines - abated)
        o_ind_emi <- p_ind_emiabat-v_ind_emiabatproc


        #report the variables
        tmp1 <- NULL
        tmp1 <- mbind(tmp1,setNames(dimSums(o_ind_emi,3)*s_c2co2*1000,"Emissions|CO2|Industry (Mt CO2/yr)"))
        tmp1 <- mbind(tmp1,setNames(dimSums(v_ind_emiabatproc,dim=3)*s_c2co2*1000,"Emissions abated|CO2|Industry (Mt CO2/yr)"))

        # read variables that have been already calculated in other functions (emissions and trade costs)
        o_elec_emi <- output[,,"Emissions|CO2|Energy|Supply|Electricity (Mt CO2/yr)"] #make regions match
        tmp1 <- mbind(tmp1,setNames(dimSums(o_ind_emi,3)*s_c2co2*1000+o_elec_emi,"Emissions|CO2|Electricity and Industry (Mt CO2/yr)"))


        #INDUSTRY COSTS
        # read variables that have been already calculated in other functions (emissions and trade costs)
        o_co2price_EUETS <- output[,,"Price|Carbon|ETS (Eur2010/t CO2)"]
        o_ind_co2price <- o_co2price_EUETS
        if(c_LIMESversion >= 2.29) {
          o_ind_co2price <- output[,,"Price|Carbon|Net|Industry (Eur2010/t CO2)"]
        }

        tmp2 <- NULL
        o_totcostabat <- dimSums(v_ind_emiabatproc*p_ind_emimac*s_c2co2,dim=3)
        tmp2 <- mbind(tmp2,setNames(o_totcostabat,"Total Cost|Industry|Abatement (billion eur2010/yr)"))

        #In previous version, there is no information about allocation of EUA to industry per region, so I just define the required EUA equal to the emissions
        o_ind_netreqEUA <-dimSums(o_ind_emi,3)*s_c2co2*1000

        if(c_bankemi_EU == 1) {
          if(c_LIMESversion >= 2.28) {
            # read variables from gdx
            p_sharecomb_freeEUA <- readGDX(gdx,name="p_sharecomb_freeEUA",field="l",format="first_found")[, y, ] #Share of free allocated certificates to combustion sector
            p_sharefreeEUA_ind <- readGDX(gdx,name="p_sharefreeEUA_ind",field="l",format="first_found") #Share fo free EUA to industry per country
            p_sharefreeEUA_ind <- limesMapping(p_sharefreeEUA_ind)
            p_freealloc_EUETS <- readGDX(gdx,name="p_freealloc_EUETS",field="l",format="first_found")[, y, ] #free allocated certificates in ETS [Gt]

            #EUA freely allocated to the industry
            o_ind_freeEUA <- p_freealloc_EUETS*(1-p_sharecomb_freeEUA)*p_sharefreeEUA_ind
            tmp2 <- mbind(tmp2,setNames(o_ind_freeEUA*s_c2co2*1000,"Emissions|CO2|Free-allocated certificates ETS|Industry (Mt CO2/yr)"))

            o_ind_netreqEUA <- (dimSums(o_ind_emi,3) - o_ind_freeEUA)*s_c2co2*1000 #in MtCO2/yr
          }

          o_totcostco2 <- pmax(o_ind_netreqEUA,0)*o_ind_co2price/1000
          tmp2 <- mbind(tmp2,setNames(o_totcostco2,"Total Cost|Industry|CO2 costs (billion eur2010/yr)"))
          o_revEUAsale <- -pmin(o_ind_netreqEUA,0)*o_ind_co2price/1000
          tmp2 <- mbind(tmp2,setNames(o_revEUAsale,"Revenues|Industry|EUA sales (billion eur2010/yr)"))
          tmp2 <- mbind(tmp2,setNames(o_revEUAsale - o_totcostabat - o_totcostco2,"Profits|Industry (billion eur2010/yr)"))
        }

        # concatenate data
        tmp <- mbind(tmp1,tmp2)
      }#end if c_industry ==1

    } #end if c_LIMESversion >=2.26

    #Additional calculations
    tmp3 <- NULL

    if(c_LIMESversion >=  2.33) {
      heating <- .readHeatingCfg(gdx)
      p_emiothersec <- readGDX(gdx,name="p_emiothersec",field="l",format="first_found")[, y, ]
      if(heating == "fullDH" & dimSums(p_emiothersec, dim = 2) == 0) { #only report emissions EU ETS at country level when all the components are at national level
        #The main problem is with p_emiothersec, which is only used at EU ETS level
        #Calculate EU ETS emissions when DH emissions are endogenous and per country
        tmp3 <- mbind(tmp3,setNames(
          output[,,"Emissions|CO2|Energy|Supply|Electricity (Mt CO2/yr)"] +
            output[,,"Emissions|CO2|Energy|Supply|Heat|District Heating (Mt CO2/yr)"] +
            tmp[,,"Emissions|CO2|Industry (Mt CO2/yr)"],
          "Emissions|CO2|EU ETS (Mt CO2/yr)"))
      }
    }

    # concatenate data
    tmp <- mbind(tmp,tmp3)



    #Add NAs to avoid inconsistencies: There are no industry emissions values for 2010 and 2015
    var_names <- c(
      "Emissions|CO2|Free-allocated certificates ETS|Industry (Mt CO2/yr)",
      "Total Cost|Industry|CO2 costs (billion eur2010/yr)",
      "Revenues|Industry|EUA sales (billion eur2010/yr)",
      "Profits|Industry (billion eur2010/yr)"
    )

    for(var in var_names) {
      if(var %in% getNames(tmp)) {
        tmp[, c(2010,2015), var] <- NA
      }
    }

    var_names <- c(
      "Emissions|CO2|Industry (Mt CO2/yr)",
      "Emissions abated|CO2|Industry (Mt CO2/yr)",
      "Emissions|CO2|Electricity and Industry (Mt CO2/yr)",
      "Total Cost|Industry|Abatement (billion eur2010/yr)"
    )

    for(var in var_names) {
      if(var %in% getNames(tmp)) {
        tmp[, c(2010), var] <- NA
      }
    }

    #End switch for EU ETS (c_bankemiEU)
  } else {

    tmp <- NULL

  }




  return(tmp)
}

