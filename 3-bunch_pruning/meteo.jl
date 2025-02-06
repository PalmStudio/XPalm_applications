# Purpose: make a meteo file that is larger that the one we have to match the growing time-frame of the plot we are simulating.
# The plot was planted in 2008 and the pruning events happened between July 2023 and July 2024. 
# We start the simulation from the seed, so we will need to generate data from 2008 - 18 months (18 until planting) to 2025.
# We repeat observations from years we measured to complete the missing data.

MAP = -17 # Months after planting for the first time-step (the seed is effectively 18 months before planting the palm into the field)

meteo = CSV.read(joinpath(dirname(dirname(pathof(XPalmModel))), "0-data/meteo.csv"), DataFrame)

extrema(meteo.date)
# 2012 starts on 01-05, copying data from 01-01 to 01-04:
meteo_2012_start = filter(row -> row.date >= Date(2013, 01, 01) && row.date <= Date(2013, 01, 04), meteo)
meteo_2012_start.date .= meteo_2012_start.date .- Year(1)
meteo = vcat(meteo_2012_start, meteo)

# Same for 2023, it ends on 05-26.
meteo_2023_end = filter(row -> row.date >= Date(2022, 05, 27) && row.date <= Date(2022, 12, 31), meteo)
meteo_2023_end.date .= meteo_2023_end.date .+ Year(1)
meteo = vcat(meteo, meteo_2023_end)

# now we need to compute the start date of the simulation:
start_date_simulation = Date(2008) - Month(18)
start_year_simulation = Dates.year(start_date_simulation)
start_year_observation = Dates.year(meteo.date[1])
n_years_before = start_year_observation - start_year_simulation

meteo_2006_to_2011 = filter(row -> row.date >= Date(2012, 01, 01) && row.date <= Date(start_year_observation + n_years_before - 1, 12, 31), meteo)
meteo_2006_to_2011.date .= meteo_2006_to_2011.date .- Year(n_years_before)
meteo = vcat(meteo_2006_to_2011, meteo)

meteo_2024_to_2026 = filter(row -> row.date >= Date(2021, 01, 01) && row.date <= Date(2023, 12, 31), meteo)
meteo_2024_to_2026.date .= meteo_2024_to_2026.date .+ Year(3)

meteo = vcat(meteo, meteo_2024_to_2026)

# Filtering the first few months of 2006:
filter!(row -> row.date >= start_date_simulation, meteo)

extrema(meteo.date)

# Controling the generated data:
meteo_long = stack(meteo, Not(:date), variable_name=:variable, value_name=:value)
data(meteo_long) * mapping(:date => "Date", :value => "Value", layout=:variable) * visual(Lines) |>
draw(facet=(; linkyaxes=:none), figure=(; size=(800, 600)), axis=(xticklabelrotation=45,))

# Saving the data to disk:
CSV.write("0-data/meteo_PR_generated_2006_2025.csv", meteo)


# If reading data from Doni:
# select!(
#     meteo,
#     :date,
#     :date => (x -> Dates.Day(1)) => :duration,
#     :timestep, :months_after_planting,
#     :T, :Tmin, :Tmax,
#     :Wind => ByRow(x -> ismissing(x) ? 0.0 : x) => :Wind,
#     :Rh => (x -> x ./ 100) => :Rh,
#     :Rh_max => (x -> x ./ 100) => :Rh_max,
#     :Rh_min => (x -> x ./ 100) => :Rh_min,
#     :solar_radiation_W_m2 => ByRow(x -> x * 60 * 60 * 24 * 1e-6 * c.PAR_fraction) => :Ri_PAR_f, # PAR in MJ m⁻² d⁻¹
#     :solar_radiation_W_m2 => ByRow(x -> x * 60 * 60 * 24 * 1e-6) => :Rg, # Global radiation in MJ m⁻² d⁻¹
# )
# dropmissing!(meteo)

# Make a plot with all variables to check the data:
# meteo_long = stack(meteo, Not(:date, :duration, :timestep, :months_after_planting), variable_name=:variable, value_name=:value)
# data(meteo_long) * mapping(:months_after_planting => "Months after planting", :value => "Value", layout=:variable) * visual(Lines) |> draw(facet=(; linkxaxes=:minimal, linkyaxes=:none))
# data(meteo_long) * mapping(:date => "Date", :value => "Value", layout=:variable) * visual(Lines) |>
# draw(facet=(; linkyaxes=:none), figure=(; size=(800, 600)), axis=(xticklabelrotation=45,))
