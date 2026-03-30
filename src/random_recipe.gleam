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
  UserClickedShowRecipeDetails
  UserClickedHideRecipeDetails
  AppStartedShowingRecipeDetails
  AppStartedHidingRecipeDetails
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

    UserClickedShowRecipeDetails ->
      case model.show_recipe_details {
        True -> #(model, effect.none())
        False -> #(model, run_view_transition(AppStartedShowingRecipeDetails))
      }

    UserClickedHideRecipeDetails ->
      case model.show_recipe_details {
        True -> #(model, run_view_transition(AppStartedHidingRecipeDetails))
        False -> #(model, effect.none())
      }

    AppStartedShowingRecipeDetails -> #(
      Model(..model, show_recipe_details: True),
      effect.none(),
    )

    AppStartedHidingRecipeDetails -> #(
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

@external(javascript, "./random_recipe_ffi.mjs", "start_view_transition")
fn start_view_transition(with callback: fn() -> Nil) -> Nil

fn run_view_transition(message: Msg) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    start_view_transition(fn() {
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
  let is_showing_details = model.show_recipe_details

  let recipe_element = case model.recipe_state {
    Showing(view_state) -> recipe_content(view_state, is_showing_details)
    Loading(option.Some(current)) -> recipe_content(current, is_showing_details)
    PlaceholderLocked(_, _) -> recipe_placeholder()
    PlaceholderReady(_) -> recipe_placeholder()
    Loading(option.None) | Empty -> recipe_placeholder()
  }

  html.div(
    [
      attribute.class(
        "min-h-screen overflow-x-hidden bg-stone-100 px-6 py-10 text-stone-900",
      ),
    ],
    [
      html.div(
        [
          attribute.class(app_shell_class(model.show_recipe_details)),
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

fn recipe_content(
  view_state: RecipeViewState,
  show_recipe_details: Bool,
) -> Element(Msg) {
  case view_state {
    RecipeLoaded(recipe) ->
      html.div([attribute.class(recipe_frame_class(show_recipe_details))], [
        html.button(
          [
            attribute.class(recipe_card_button_class(show_recipe_details)),
            event.on_click(UserClickedShowRecipeDetails),
            attribute.aria_label("Show recipe details"),
          ],
          [
            html.div(
              [
                attribute.class(recipe_card_surface_class(show_recipe_details)),
                attribute.style("view-transition-name", "recipe-card"),
              ],
              [
                html.div(
                  [
                    attribute.class(recipe_media_wrap_class(show_recipe_details)),
                  ],
                  [
                    html.div(
                      [
                        attribute.class(recipe_media_class(show_recipe_details)),
                        attribute.style("view-transition-name", "recipe-image"),
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
                    html.div(
                      [
                        attribute.class(recipe_summary_class(
                          show_recipe_details,
                        )),
                      ],
                      [
                        html.p(
                          [
                            attribute.class(
                              "text-xs font-semibold uppercase tracking-[0.24em] text-stone-500",
                            ),
                          ],
                          [
                            html.text(option.unwrap(recipe.category, "Category")),
                          ],
                        ),
                        html.h1(
                          [
                            attribute.class(
                              "max-w-xl text-3xl font-semibold leading-tight text-stone-950 sm:text-4xl",
                            ),
                            attribute.style(
                              "view-transition-name",
                              "recipe-title",
                            ),
                          ],
                          [html.text(recipe.name)],
                        ),
                        html.div(
                          [
                            attribute.class(details_panel_class(
                              show_recipe_details,
                            )),
                          ],
                          [
                            html.p(
                              [
                                attribute.class(
                                  "text-xs font-semibold uppercase tracking-[0.24em] text-stone-400",
                                ),
                              ],
                              [html.text("Description")],
                            ),
                            html.p(
                              [
                                attribute.class(
                                  "max-w-prose overflow-y-auto pr-2 text-sm leading-7 text-stone-600 sm:text-base",
                                ),
                              ],
                              [
                                html.text(option.unwrap(
                                  recipe.instructions,
                                  "No description yet.",
                                )),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                html.div(
                  [attribute.class(arrow_wrap_class(show_recipe_details))],
                  [
                    html.div(
                      [
                        attribute.class(
                          "flex h-12 w-12 items-center justify-center rounded-full bg-stone-900 text-lg text-stone-50 shadow-lg shadow-stone-950/15 transition-transform duration-300 group-hover:translate-x-1 group-hover:-translate-y-1",
                        ),
                      ],
                      [html.text("->")],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        html.button(
          [
            attribute.class(close_button_class(show_recipe_details)),
            event.on_click(UserClickedHideRecipeDetails),
            attribute.aria_label("Hide recipe details"),
          ],
          [html.text("x")],
        ),
      ])

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

fn app_shell_class(show_recipe_details: Bool) -> String {
  case show_recipe_details {
    True ->
      "mx-auto flex min-h-[calc(100vh-5rem)] max-w-md flex-col items-center justify-center gap-6 transition-all duration-500 ease-out"
    False ->
      "mx-auto flex min-h-[calc(100vh-5rem)] max-w-md flex-col items-center justify-center gap-6 transition-all duration-500 ease-out"
  }
}

fn recipe_frame_class(show_recipe_details: Bool) -> String {
  case show_recipe_details {
    True ->
      "fixed inset-0 z-40 h-screen overflow-hidden bg-stone-100 transition-all duration-700 ease-[cubic-bezier(0.22,1,0.36,1)]"
    False ->
      "relative w-full transition-all duration-700 ease-[cubic-bezier(0.22,1,0.36,1)]"
  }
}

fn recipe_card_button_class(show_recipe_details: Bool) -> String {
  case show_recipe_details {
    True ->
      "group relative block h-screen w-full cursor-default overflow-hidden text-left outline-none transition-all duration-700 ease-[cubic-bezier(0.22,1,0.36,1)]"
    False ->
      "group relative mx-auto block w-full cursor-pointer text-left outline-none transition-all duration-500 ease-[cubic-bezier(0.22,1,0.36,1)] hover:-translate-y-2"
  }
}

fn recipe_card_surface_class(show_recipe_details: Bool) -> String {
  case show_recipe_details {
    True ->
      "relative flex h-screen w-full overflow-hidden bg-stone-100 transition-all duration-700 ease-[cubic-bezier(0.22,1,0.36,1)]"
    False ->
      "relative w-full overflow-hidden rounded-[2rem] border border-stone-200 bg-white shadow-[0_24px_80px_rgba(28,25,23,0.08)] transition-all duration-500 ease-[cubic-bezier(0.22,1,0.36,1)] group-hover:shadow-[0_32px_100px_rgba(28,25,23,0.14)]"
  }
}

fn recipe_media_wrap_class(show_recipe_details: Bool) -> String {
  case show_recipe_details {
    True ->
      "mx-auto grid h-screen w-full max-w-[1200px] grid-cols-1 items-center gap-6 px-6 py-20 lg:grid-cols-[minmax(0,460px)_minmax(0,1fr)] lg:gap-12"
    False -> "flex flex-col"
  }
}

fn recipe_media_class(show_recipe_details: Bool) -> String {
  case show_recipe_details {
    True ->
      "aspect-square w-full self-center overflow-hidden rounded-[2.5rem] bg-stone-200 shadow-[0_30px_90px_rgba(28,25,23,0.14)] transition-all duration-700 ease-[cubic-bezier(0.22,1,0.36,1)] lg:h-[calc(100vh-10rem)] lg:max-h-[720px] lg:aspect-auto"
    False -> "aspect-square w-full overflow-hidden bg-stone-200"
  }
}

fn recipe_summary_class(show_recipe_details: Bool) -> String {
  case show_recipe_details {
    True -> "flex h-full min-h-0 flex-col justify-center gap-6 py-2 lg:py-6"
    False -> "flex flex-col gap-3 p-6"
  }
}

fn details_panel_class(show_recipe_details: Bool) -> String {
  case show_recipe_details {
    True ->
      "mt-2 flex min-h-0 max-w-xl flex-1 flex-col gap-4 overflow-hidden border-t border-stone-200 pt-6 opacity-100 transition-all duration-700 ease-[cubic-bezier(0.22,1,0.36,1)]"
    False -> "pointer-events-none max-h-0 overflow-hidden opacity-0"
  }
}

fn arrow_wrap_class(show_recipe_details: Bool) -> String {
  case show_recipe_details {
    True -> "pointer-events-none absolute bottom-6 right-6 opacity-0"
    False -> "pointer-events-none absolute bottom-6 right-6 opacity-100"
  }
}

fn close_button_class(show_recipe_details: Bool) -> String {
  case show_recipe_details {
    True ->
      "fixed left-6 top-6 z-50 flex h-12 w-12 items-center justify-center rounded-full border border-stone-200 bg-white text-xl font-medium text-stone-700 shadow-lg transition-all duration-300 hover:bg-stone-50"
    False ->
      "pointer-events-none absolute left-7 top-7 z-40 h-0 w-0 overflow-hidden opacity-0"
  }
}
