import gleam/dynamic/decode
import gleam/javascript/promise
import gleam/option

import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import rsvp

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

type Model {
  Model(recipe_state: RecipeState, show_recipe_details: Bool)
}

type Recipe {
  Recipe(
    id: String,
    name: String,
    name_alt: option.Option(String),
    category: option.Option(String),
    area: option.Option(String),
    instructions: option.Option(String),
    thumbnail_url: option.Option(String),
  )
}

type RecipeViewState {
  RecipeLoaded(Recipe)
  RecipeFailed(String)
}

type RecipeState {
  Empty
  Showing(RecipeViewState)
  Loading(option.Option(RecipeViewState))
  PlaceholderLocked(
    current: option.Option(RecipeViewState),
    pending: option.Option(RecipeViewState),
  )
  PlaceholderReady(option.Option(RecipeViewState))
}

fn init(_args) -> #(Model, Effect(Msg)) {
  let model = Model(recipe_state: Empty, show_recipe_details: False)
  start_recipe_request(model)
}

type Msg {
  UserClickedGetRandomRecipe
  UserClickedOpenRecipeDetails
  UserClickedCloseRecipeDetails
  AppPlaceholderDelayElapsed
  AppPlaceholderMinimumElapsed
  ApiReturnedRecipe(Result(Recipe, rsvp.Error))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserClickedGetRandomRecipe ->
      case is_loading(model.recipe_state) {
        True -> #(model, effect.none())
        False -> start_recipe_request(model)
      }

    UserClickedOpenRecipeDetails -> #(
      Model(..model, show_recipe_details: True),
      effect.none(),
    )

    UserClickedCloseRecipeDetails -> #(
      Model(..model, show_recipe_details: False),
      effect.none(),
    )

    AppPlaceholderDelayElapsed ->
      case model.recipe_state {
        Loading(current) -> #(
          Model(
            ..model,
            recipe_state: PlaceholderLocked(current:, pending: option.None),
          ),
          delay_message(
            placeholder_minimum_duration_ms,
            AppPlaceholderMinimumElapsed,
          ),
        )
        _ -> #(model, effect.none())
      }

    AppPlaceholderMinimumElapsed ->
      case model.recipe_state {
        PlaceholderLocked(_, option.Some(pending)) -> #(
          Model(recipe_state: Showing(pending), show_recipe_details: False),
          effect.none(),
        )

        PlaceholderLocked(current, option.None) -> #(
          Model(..model, recipe_state: PlaceholderReady(current)),
          effect.none(),
        )

        _ -> #(model, effect.none())
      }

    ApiReturnedRecipe(response) ->
      case model.recipe_state {
        PlaceholderLocked(current, _) -> #(
          Model(
            ..model,
            recipe_state: PlaceholderLocked(
              current: current,
              pending: option.Some(recipe_view_state(response)),
            ),
          ),
          effect.none(),
        )

        _ -> #(
          Model(
            recipe_state: Showing(recipe_view_state(response)),
            show_recipe_details: False,
          ),
          effect.none(),
        )
      }
  }
}

const placeholder_delay_ms = 150

const placeholder_minimum_duration_ms = 150

fn start_recipe_request(model: Model) -> #(Model, Effect(Msg)) {
  let current = case model.recipe_state {
    Showing(view_state) -> option.Some(view_state)
    Loading(current) -> current
    PlaceholderLocked(current, _) -> current
    PlaceholderReady(current) -> current
    Empty -> option.None
  }

  #(
    Model(recipe_state: Loading(current), show_recipe_details: False),
    effect.batch([
      get_random_recipe(),
      delay_message(placeholder_delay_ms, AppPlaceholderDelayElapsed),
    ]),
  )
}

fn is_loading(recipe_state: RecipeState) -> Bool {
  case recipe_state {
    Loading(_) | PlaceholderLocked(_, _) | PlaceholderReady(_) -> True
    _ -> False
  }
}

fn recipe_view_state(response: Result(Recipe, rsvp.Error)) -> RecipeViewState {
  case response {
    Ok(recipe) -> RecipeLoaded(recipe)
    Error(_) -> RecipeFailed("Something went wrong")
  }
}

fn delay_message(delay_ms: Int, message: Msg) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    promise.wait(delay_ms)
    |> promise.map(fn(_) {
      dispatch(message)
      Nil
    })

    Nil
  })
}

fn get_random_recipe() -> Effect(Msg) {
  let recipe_decoder = {
    use id <- decode.field("idMeal", decode.string)
    use name <- decode.field("strMeal", decode.string)
    use name_alt <- decode.optional_field(
      "strMealAlternate",
      option.None,
      decode.optional(decode.string),
    )
    use category <- decode.optional_field(
      "strCategory",
      option.None,
      decode.optional(decode.string),
    )
    use area <- decode.optional_field(
      "strArea",
      option.None,
      decode.optional(decode.string),
    )
    use instructions <- decode.optional_field(
      "strInstructions",
      option.None,
      decode.optional(decode.string),
    )
    use thumbnail_url <- decode.optional_field(
      "strMealThumb",
      option.None,
      decode.optional(decode.string),
    )

    decode.success(Recipe(
      id:,
      name:,
      name_alt:,
      category:,
      area:,
      instructions:,
      thumbnail_url:,
    ))
  }

  let decoder = {
    use recipe <- decode.field("meals", decode.at([0], recipe_decoder))
    decode.success(recipe)
  }

  rsvp.get(
    "https://www.themealdb.com/api/json/v1/1/random.php",
    rsvp.expect_json(decoder, ApiReturnedRecipe),
  )
}

fn view(model: Model) -> Element(Msg) {
  let recipe_element = case model.recipe_state {
    Showing(view_state) -> recipe_content(view_state)
    Loading(option.Some(current)) -> recipe_content(current)
    PlaceholderLocked(_, _) -> recipe_placeholder()
    PlaceholderReady(_) -> recipe_placeholder()
    Loading(option.None) | Empty -> recipe_placeholder()
  }

  html.div(
    [
      attribute.class("min-h-screen bg-stone-100 px-6 py-10 text-stone-900"),
    ],
    [
      html.div(
        [
          attribute.class(
            "mx-auto flex min-h-[calc(100vh-5rem)] max-w-md flex-col items-center justify-center gap-6",
          ),
        ],
        [
          html.div([], [
            html.button(
              [
                attribute.class(
                  "inline-flex items-center justify-center rounded-full bg-stone-900 px-5 py-3 text-sm font-medium text-stone-50 transition disabled:cursor-wait disabled:opacity-60",
                ),
                event.on_click(UserClickedGetRandomRecipe),
                attribute.disabled(is_loading(model.recipe_state)),
                attribute.aria_busy(is_loading(model.recipe_state)),
              ],
              [
                html.text(case is_loading(model.recipe_state) {
                  True -> "Loading..."
                  False -> "Get random recipe"
                }),
              ],
            ),
          ]),
          html.div([attribute.class("w-full")], [recipe_element]),
        ],
      ),
    ],
  )
}

fn recipe_content(view_state: RecipeViewState) -> Element(Msg) {
  case view_state {
    RecipeLoaded(recipe) ->
      html.div(
        [
          attribute.class(
            "w-full overflow-hidden rounded-[2rem] border border-stone-200 bg-white shadow-[0_24px_80px_rgba(28,25,23,0.08)]",
          ),
        ],
        [
          html.div(
            [
              attribute.class(
                "aspect-square w-full overflow-hidden bg-stone-200",
              ),
            ],
            [
              html.img([
                attribute.class("h-full w-full object-cover"),
                attribute.src(option.unwrap(recipe.thumbnail_url, "")),
                attribute.alt(recipe.name),
                attribute.width(400),
                attribute.height(400),
              ]),
            ],
          ),
          html.div([attribute.class("flex flex-col gap-3 p-6")], [
            html.p(
              [
                attribute.class(
                  "text-xs font-semibold uppercase tracking-[0.24em] text-stone-500",
                ),
              ],
              [html.text(option.unwrap(recipe.category, "Category"))],
            ),
            html.h1(
              [
                attribute.class(
                  "text-3xl font-semibold leading-tight text-stone-950",
                ),
              ],
              [html.text(recipe.name)],
            ),
          ]),
        ],
      )

    RecipeFailed(error) ->
      html.div(
        [
          attribute.class(
            "w-full rounded-[2rem] border border-red-200 bg-red-50 p-6 text-sm text-red-700",
          ),
        ],
        [html.text(error)],
      )
  }
}

fn recipe_placeholder() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "w-full overflow-hidden rounded-[2rem] border border-stone-200 bg-white shadow-[0_24px_80px_rgba(28,25,23,0.08)]",
      ),
    ],
    [
      html.div(
        [
          attribute.class("aspect-square w-full bg-stone-200"),
        ],
        [],
      ),
      html.div([attribute.class("flex flex-col gap-3 p-6")], [
        html.div([attribute.class("h-3 w-28 rounded-full bg-stone-200")], []),
        html.div([attribute.class("h-10 w-3/4 rounded-2xl bg-stone-200")], []),
      ]),
    ],
  )
}
