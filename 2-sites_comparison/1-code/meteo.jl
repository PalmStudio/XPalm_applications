using PlantMeteo
using DataFrames, CSV, Dates
using CodecBzip2

#! Number of months after planting for the first time-step:
MAP_0 = -18 # It is negative because we start from the seed

# Importing some constants:
c = PlantMeteo.Constants()

# Reading the meteo data for all three sites (gap-filled):

meteo_raw = open(Bzip2DecompressorStream, "0-data/Meteo_predictions_all_sites.csv.bz2") do io
    CSV.read(io, DataFrame)
end


# Transforming the data and keeping only the columns we need:
select!(
    meteo_raw,
    :Site,
    :ObservationDate => :date,
    :ObservationDate => (x -> Dates.Day(1)) => :duration,
    :TAverage_pred => :T,
    :TMin_pred => :Tmin,
    :TMax_pred => :Tmax,
    :WindSpeed_pred => :Wind,
    :HRAverage_pred => (x -> x ./ 100) => :Rh,
    :HRMax_pred => (x -> x ./ 100) => :Rh_max,
    :HRMin_pred => (x -> x ./ 100) => :Rh_min,
    :Rainfall_pred => :Precipitations,
    :PAR_pred => :Ri_PAR_f, # PAR in MJ m⁻² d⁻¹
    :PAR_pred => (x -> x ./ c.PAR_fraction) => :Rg, # Global radiation in MJ m⁻² d⁻¹
)

dropmissing!(meteo_raw)
sort!(meteo_raw, [:Site, :date])

# Keeping only the common periods between the three sites:
common_periods = combine(combine(groupby(meteo_raw, :Site), :date => minimum => :start_date, :date => maximum => :end_date), :start_date => maximum => :start_date, :end_date => minimum => :end_date)
filter!(row -> common_periods.start_date[1] <= row.date <= common_periods.end_date[1], meteo_raw)
meteo_cleaned = transform(groupby(meteo_raw, :Site), eachindex => :timestep)

# Adding the year-month column to the data:
meteo_cleaned.yearmonth = [Date(Dates.yearmonth(d)...) for d in meteo_cleaned.date]
# Computes the index of the month since the beginning of the simulation:
meteo_cleaned.months_after_planting = groupindices(groupby(meteo_cleaned, :yearmonth)) .+ MAP_0
# Removing the year-month, and arranging the columns:
select!(
    meteo_cleaned,
    :Site,
    :date,
    :timestep,
    :duration,
    :months_after_planting,
    :T,
    :Tmin,
    :Tmax,
    :Wind,
    :Rh,
    :Rh_max,
    :Rh_min,
    :Precipitations,
    :Ri_PAR_f,
    :Rg
)

# Make a plot with all variables to check the data:
meteo_long = stack(meteo_cleaned, Not(:Site, :date, :timestep, :duration, :months_after_planting), variable_name=:variable, value_name=:value)
# data(meteo_long) * mapping(:months_after_planting => "Months after planting", :value => "Value", layout=:variable) * visual(Lines) |> draw(facet=(; linkxaxes=:minimal, linkyaxes=:none))
data(meteo_long) * mapping(:date => "Date", :value => "Value", layout=:variable, color=:Site) * visual(Lines) |>
draw(facet=(; linkyaxes=:none), figure=(; size=(800, 600)), axis=(xticklabelrotation=45,))


CSV.write("0-data/Meteo_predictions_all_sites_cleaned.csv", meteo_cleaned)

# CSV.write("0-data/Meteo_Nigeria_PR.csv", select(filter(x -> x.Site == "PR", meteo_cleaned), Not(:Site, :timestep, :duration, :months_after_planting)))