using XPalm, XPalm.Models, PlantSimEngine
using MultiScaleTreeGraph, PlantMeteo
using CSV, DataFrames, YAML
using Dates
using CairoMakie, AlgebraOfGraphics

c = PlantMeteo.Constants()

includet("leaf_pruning_model.jl")
includet("model_mapping.jl")
parameters = YAML.load_file(joinpath(dirname(@__FILE__), "0-data", "xpalm_parameters.yml"), dicttype=Dict{Symbol,Any})

meteo = CSV.read("0-data/meteo_PR_generated_2006_2025.csv", DataFrame)

# filter!(row -> row.date < Date(2022), meteo) # filtering the data to avoid the year 2022 that is not complete
meteo.timestep .= 1:nrow(meteo)
# Adding the year-month column to the data:
meteo.yearmonth = [Date(Dates.yearmonth(d)...) for d in meteo.date]

# Computes the index of the month since the beginning of the simulation:
MAP_0 = -18 # It is negative because we start from the seed
meteo.months_after_planting = groupindices(groupby(meteo, :yearmonth)) .+ MAP_0

meteo_w = Weather(meteo)

rank_leaves_left = collect(25:5:50)
durations_windows = [Month(6), Month(12)] # duration of the pruning, in days: 6 months and 12 months
age_start = fill(Date(2023, 07, 01), length(durations_windows)) # age start of the window in days
time_windows = collect(zip(age_start, durations_windows))

# Make all combinations of time_windows and rank_leaves_left:
combinations = [(; rank, window) for rank in rank_leaves_left for window in time_windows]

out_vars = Dict{String,Any}(
    "Scene" => (:lai, :aPPFD),
    "Leaf" => (
        :Rm, :carbon_demand, :carbon_allocation, :biomass, :leaf_area, :reserve, :rank, :state, :pruning_decision
    ),
    "Female" => (
        :carbon_demand, :carbon_allocation, :biomass, :fruits_number, :state, :biomass_fruit_harvested,
        :biomass_stalk, :biomass_bunch_harvested
    ),
    "Plant" => (
        :ftsw, :carbon_allocation, :biomass_bunch_harvested, :biomass_fruit_harvested,
        :carbon_assimilation, :reserve, :carbon_demand, :carbon_offer_after_allocation, :carbon_offer_after_rm, :leaf_area,
        :n_bunches_harvested, :biomass_bunch_harvested_cum, :n_bunches_harvested_cum, :phytomer_count,
    ),
)

simulations = DataFrame[]
for i in combinations
    parameters[:management][:manual_pruning] = Dict{Symbol,Any}(
        :rank => i.rank,
        :start_date => i.window[1],
        :duration => i.window[2]
    )

    palm = XPalm.Palm(initiation_age=0, parameters=parameters)
    models = model_mapping_theft(palm)
    out = PlantSimEngine.run!(palm.mtg, models, meteo_w, outputs=out_vars, executor=PlantSimEngine.SequentialEx(), check=false)
    df = PlantSimEngine.outputs(out, DataFrame, no_value=missing)
    df[!, "rank_leaves_left"] .= i.rank
    df[!, "window_duration"] .= i.window[2]
    push!(simulations, df)
end

# Declaring aesthetics:
rank_leaves_left_aes = :rank_leaves_left => nonnumeric => "Leaves"
df_pruning = DataFrame([
    (duration=i[2], start_map=only(filter(x -> x.date == i[1], meteo)).months_after_planting, end_map=only(filter(x -> x.date == i[1] + i[2], meteo)).months_after_planting) for i in time_windows
])

function pruning_aes(max_value, df_pruning)
    geometry_pruning = [Rect(i.start_map, 0.0, i.end_map - i.start_map, max_value) for i in eachrow(df_pruning)]
    data((; geometry_pruning, duration=df_pruning.duration, Pruning=string.(df_pruning.duration))) *
    mapping(:geometry_pruning, col=:duration, color=:Pruning => AlgebraOfGraphics.scale(:tertiary)) *
    visual(Poly, alpha=0.5)
end

planting_aes = mapping([0], color="Planting" => AlgebraOfGraphics.scale(:secondary)) * visual(VLines, linestyle=:dash)
planting_aes_year = mapping([age_start[1]], color="Planting" => AlgebraOfGraphics.scale(:secondary)) * visual(VLines, linestyle=:dash)

# Adding the dates to the simulations:
dfs_all = vcat(simulations...)
dfs_all = leftjoin(dfs_all, meteo, on=:timestep)
sort!(dfs_all, :timestep)

df_scene = filter(x -> x.organ == "Scene", dfs_all)
dfs_scene_months = combine(
    groupby(df_scene, [:months_after_planting, :rank_leaves_left, :window_duration]),
    :lai => maximum => :lai
)

p_lai =
    pruning_aes(maximum(dfs_scene_months.lai), df_pruning) +
    data(dfs_scene_months) *
    mapping(:months_after_planting => "Months after planting", :lai => "Leaf Area Index (m² m⁻²)", color=rank_leaves_left_aes, col=:window_duration) *
    visual(Lines) +
    planting_aes |>
    draw(figure=(size=(800, 600),))

save("outputs/lai.png", p_lai, px_per_unit=3)

#! Plant scale
dfs_plant = filter(row -> row[:organ] == "Plant", dfs_all)
select!(dfs_plant, findall(x -> any(!ismissing(i) for i in x), eachcol(dfs_plant)))

dfs_plant_month = combine(
    groupby(dfs_plant, [:months_after_planting, :rank_leaves_left, :window_duration]),
    :date => (x -> Date(yearmonth(x[1])...)) => :date,
    :timestep => (x -> x[end] - x[1] + 1) => :nb_timesteps,
    :biomass_bunch_harvested => sum => :biomass_bunch_harvested_monthly,
    :biomass_bunch_harvested_cum => last => :biomass_bunch_harvested_cum,
    :n_bunches_harvested => sum => :n_bunches_harvested_monthly,
    :n_bunches_harvested_cum => last => :n_bunches_harvested_cum,
    :phytomer_count => last => :phytomer_count,
    :phytomer_count => (x -> x[end] - x[1]) => :phytomer_emmitted,
)

dfs_plant_year = combine(
    groupby(transform(dfs_plant, :date => ByRow(year) => :year), [:year, :rank_leaves_left, :window_duration]),
    :timestep => (x -> x[end] - x[1] + 1) => :nb_timesteps,
    :biomass_bunch_harvested => sum => :biomass_bunch_harvested,
    :biomass_fruit_harvested => sum => :biomass_fruit_harvested,
    :biomass_bunch_harvested_cum => last => :biomass_bunch_harvested_cum
)

CC_Fruit = 0.4857     # Fruit carbon content (gC g-1 dry mass)
water_content_mesocarp = 0.25  # Water content of the mesocarp
dry_to_fresh_ratio = 1 / (1 - water_content_mesocarp)  # Based on the mesocarp water content of 0.3

#! FFB in kg plant-1 year-1 should be around 100-200 kg according to Van Kraalingen et al. 1989 (may be way higher now):
p_ffb_year_plant =
    data(dfs_plant_year) *
    mapping(:year => Date => "Date", :biomass_bunch_harvested => (x -> x * 1e-3 / CC_Fruit * dry_to_fresh_ratio) => "FFB (kg plant⁻¹ year⁻¹)", color=rank_leaves_left_aes, col=:window_duration) *
    visual(Lines) |>
    draw(figure=(size=(1200, 600),))
save("outputs/ffb_year_plant.png", p_ffb_year_plant, px_per_unit=3)

p_ffb_month_plant =
    pruning_aes(120, df_pruning) +
    data(dfs_plant_month) *
    mapping(:months_after_planting => "Months after planting", :biomass_bunch_harvested_monthly => (x -> x * 1e-3 / CC_Fruit * dry_to_fresh_ratio) => "FFB (kg plant⁻¹ month⁻¹)", color=rank_leaves_left_aes, col=:window_duration) *
    visual(Scatter) + planting_aes |>
    draw(figure=(size=(800, 600),))
save("outputs/ffb_month_plant.png", p_ffb_month_plant, px_per_unit=3)

p_ffb_cum_plant =
    pruning_aes(6000, df_pruning) +
    data(dfs_plant_month) *
    mapping(:months_after_planting => "Months after planting", :biomass_bunch_harvested_cum => (x -> x * 1e-3 / CC_Fruit * dry_to_fresh_ratio) => "Cumulated FFB (kg plant⁻¹)", color=rank_leaves_left_aes, col=:window_duration) *
    visual(Lines) + planting_aes |>
    draw(figure=(size=(800, 600),))
save("outputs/ffb_year_cum_plant.png", p_ffb_cum_plant, px_per_unit=3)

#! FFB (yield, t ha-1):
p_ffb_year_plot = data(dfs_plant_year) * mapping(:year => Date => "Date", :biomass_bunch_harvested => (x -> x * 1e-6 / CC_Fruit * dry_to_fresh_ratio / parameters[:scene_area] * 10000) => "FFB (t ha⁻¹ year⁻¹)", color=rank_leaves_left_aes, col=:window_duration) * visual(Lines) |> draw()
save("outputs/ffb_year_plot.png", p_ffb_year_plot, px_per_unit=3, resolution=(800, 600))
p_fruits_year_plot = data(dfs_plant_year) * mapping(:year => Date => "Date", :biomass_fruit_harvested => (x -> x * 1e-6 / CC_Fruit * dry_to_fresh_ratio / parameters[:scene_area] * 10000) => "Fruit yield (t ha⁻¹ year⁻¹)", color=rank_leaves_left_aes, col=:window_duration) * visual(Lines) |> draw()
save("outputs/p_fruit_yields_year_plot.png", p_fruits_year_plot, px_per_unit=3, resolution=(800, 600))

p_ffb_cum_year_plot = data(dfs_plant_month) * mapping(:months_after_planting => "Months after planting", :biomass_bunch_harvested_cum => (x -> x * 1e-6 / CC_Fruit * dry_to_fresh_ratio / parameters[:scene_area] * 10000) => "Cumulated FFB (t ha⁻¹)", color=rank_leaves_left_aes, col=:window_duration) * visual(Lines) |> draw()
save("outputs/ffb_year_cum_plot.png", p_ffb_cum_year_plot, px_per_unit=3)

df_ffb = combine(
    groupby(dfs_plant_year, [:rank_leaves_left, :window_duration]),
    :biomass_bunch_harvested_cum => (x -> last(x) * 1e-6 / CC_Fruit * dry_to_fresh_ratio / parameters[:scene_area] * 10000) => :biomass_bunch_harvested_cum_t_ha,
)

df_during_and_after_window = combine(
    groupby(filter(x -> x.year >= year(age_start[1]), dfs_plant_year), [:rank_leaves_left, :window_duration]),
    :biomass_bunch_harvested => (x -> sum(x) * 1e-6 / CC_Fruit * dry_to_fresh_ratio / parameters[:scene_area] * 10000) => :biomass_bunch_harvested_cum_t_ha,
)

df_after_window = combine(
    groupby(filter(x -> x.year > year(age_start[1]), dfs_plant_year), [:rank_leaves_left, :window_duration]),
    :biomass_bunch_harvested => (x -> sum(x) * 1e-6 / CC_Fruit * dry_to_fresh_ratio / parameters[:scene_area] * 10000) => :biomass_bunch_harvested_cum_t_ha,
)

1 - 179.1 / 184
1 - 171.0 / 184

p_bar_ffb_cum = data(df_ffb) * mapping(:window_duration => string, :biomass_bunch_harvested_cum_t_ha => "Cumulated FFB 2008-2026 (t ha⁻¹)", color=:rank_leaves_left => "Leaves", dodge_x=rank_leaves_left_aes) * visual(BarPlot) |> draw
save("outputs/ffb_cum_all.png", p_bar_ffb_cum, px_per_unit=3)
p_bar_ffb_cum_during_and_after_window = data(df_during_and_after_window) * mapping(:window_duration => string, :biomass_bunch_harvested_cum_t_ha => "Cumulated FFB July 2023-2026 (t ha⁻¹)", color=:rank_leaves_left => "Leaves", dodge_x=rank_leaves_left_aes) * visual(BarPlot) |> draw
save("outputs/ffb_cum_during_and_after.png", p_bar_ffb_cum_during_and_after_window, px_per_unit=3)
p_bar_ffb_cum_after_window = data(df_after_window) * mapping(:window_duration => string, :biomass_bunch_harvested_cum_t_ha => "Cumulated FFB 2025-2026 (t ha⁻¹)", color=:rank_leaves_left => "Leaves", dodge_x=rank_leaves_left_aes) * visual(BarPlot) |> draw
save("outputs/ffb_cum_after.png", p_bar_ffb_cum_after_window, px_per_unit=3)


df_leaf = filter(x -> x.organ == "Leaf", dfs_all)
select!(df_leaf, findall(x -> any(!ismissing(i) for i in x), eachcol(df_leaf)))


# Count the number of leaves at the begining of the pruning treatment:
# df_leaf_start_pruning = filter(x -> x.date == age_start[1] + Day(1) && x.window_duration == Month(6) && x.rank_leaves_left == 25, df_leaf)
df_leaf_start_pruning = filter(x -> x.date >= age_start[1] + Day(1) && x.window_duration == Month(6) && x.rank_leaves_left == 25, df_leaf)
# df_leaf_start_pruning.leaf_area[df_leaf_start_pruning.state.=="Opened"]
# df_leaf_start_pruning.leaf_area[df_leaf_start_pruning.pruning_decision.=="Pruned during time window"]

df_opened = filter(x -> x.state .== "Opened", df_leaf_start_pruning)
df_opened_ts = combine(groupby(df_opened, :timestep, sort=true), :leaf_area => sum => :leaf_area)
scatter(df_opened_ts.timestep, df_opened_ts.leaf_area ./ 73.52941176470588)
scatter(filter(x -> x.state .== "Opened", df_leaf_start_pruning).leaf_area) / 73.52941176470588


filter(x -> x.pruning_decision == "Pruned during time window", df_leaf_start_pruning)

filter(x -> x.pruning_decision == "Pruned during time window", df_leaf)

