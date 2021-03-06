port module Main exposing (main)

import Browser
import Browser.Dom
import Browser.Events
import Html exposing (Html)
import Html.Events
import Simulation
import Element as E
import Element.Input as Input
import Element.Background as Background
import Element.Font as Font
import Element.Border as Border
import Json.Encode as Encode
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Field as Field
import List.Extra
import File exposing (File)
import File.Select
import File.Download
import Task
import ColorPicker
import Color
import FeatherIcons
import Utils exposing (styles, colors, centeredText, toElmUiColor)


port pageWillClose : (() -> msg) -> Sub msg
port saveProject : Encode.Value -> Cmd msg
port downloadModelAsSvg : String -> Cmd msg


type alias Model =
  { simulations : List Simulation.Model
  , activeSimulation : Simulation.Model
  , defaultSimulationIndex : Int
  , uploadResult : UploadResult
  , popUp : PopUp
  , pendingSettings : Simulation.Settings
  , simulationWidth : Float
  , simulationHeight : Float
  , positiveChargeColorPicker : ColorPicker.State
  , positiveLineColorPicker : ColorPicker.State
  , negativeChargeColorPicker : ColorPicker.State
  , negativeLineColorPicker : ColorPicker.State
  , backgroundColorPicker : ColorPicker.State
  }


type PopUp
  = HelpPopUp
  | SettingsPopUp
  | ApplyOptionsPopUp
  | DownloadPopUp
  | UploadPopUp
  | NoPopUp


type UploadResult
  = UploadSuccess
  | UploadFailure Decode.Error
  | UploadPending


type Msg
  = UpdateActiveSimulationName String
  | ChangeActiveSimulation Simulation.Model
  | SimulationMsg Simulation.Msg
  | AddSimulation
  | RemoveSimulation Simulation.Model
  | SaveProject
  | ShowPopUp PopUp
  | UpdatePendingSetting String String
  | ApplyPendingSettings
  | ApplySettingsToFutureFields
  | ApplySettingsToCurrentAndFutureFields
  | CloseSettingsPopUp
  | CloseHelpPopUp
  | DownloadModelAsSvg
  | DownloadModelAsJson
  | CloseDownloadPopUp
  | JsonRequested
  | JsonSelected File
  | JsonLoaded String
  | CloseUploadPopUp
  | GotViewport Browser.Dom.Viewport
  | WindowResized Int Int
  | ToggleShowSourceValue Bool
  | PickSimulationColors String ColorPicker.Msg
  | UpdateActiveSimulationState
  | DoNothing
  

defaultSimulationWidth : Float
defaultSimulationWidth =
  1200


defaultSimulationHeight : Float
defaultSimulationHeight =
  750


init : (Maybe String) -> (Model, Cmd Msg)
init savedProject =
  let
    (simulation, simulationCmd) =
      Simulation.init defaultSimulationWidth defaultSimulationHeight
    project =
      case savedProject of
        Just projectJson ->
          Result.withDefault defaultProject <| Decode.decodeString decodeProject projectJson
        Nothing ->
          defaultProject
    
    defaultActiveSimulation =
      if simulation.name == Simulation.defaultName then
        { simulation
          | name =
            getDefaultSimulationName 1
        }
      else
        simulation
    
    defaultSimulations =
      [ defaultActiveSimulation ]
    
    defaultProject =
      { simulations =
        defaultSimulations
      , activeSimulation =
        defaultActiveSimulation
      , defaultSimulationIndex =
        1
      , uploadResult = UploadPending
      , popUp = NoPopUp
      , pendingSettings = Simulation.defaultSettings
      , simulationWidth = defaultSimulationWidth
      , simulationHeight = defaultSimulationHeight
      , positiveChargeColorPicker = ColorPicker.empty
      , positiveLineColorPicker = ColorPicker.empty
      , negativeChargeColorPicker = ColorPicker.empty
      , negativeLineColorPicker = ColorPicker.empty
      , backgroundColorPicker = ColorPicker.empty
      }
  in
  ( project
  , Cmd.batch
    [ Task.perform GotViewport Browser.Dom.getViewport
    , Cmd.map SimulationMsg simulationCmd
    ]
  )


view : Model -> Html Msg
view model =
  E.layout
    [ E.width E.fill
    , E.height E.fill
    , Font.size 16
    , Font.family
      [ Font.monospace
      ]
    , Background.color <| toElmUiColor model.activeSimulation.settings.colors.background
    ] <|
    E.el
      [ E.above <| viewTabs model
      , E.inFront <| viewPopUp model
      , E.below <| viewControlPanel model
      , E.centerX
      , E.centerY
      ]
      (E.html (Html.map SimulationMsg <| Simulation.view model.activeSimulation))


viewTabs : Model -> E.Element Msg
viewTabs model =
  E.row
    [ E.spacing 10
    ] <|
    List.map
      (\simulation ->
        if simulation == model.activeSimulation then
          Input.text
            ( styles.tab
              ++ [ Background.color colors.white
              , E.padding 15
              , E.inFront <| viewCloseTabButton simulation
              ]
            )
            { label = Input.labelHidden "current simulation name"
            , onChange = UpdateActiveSimulationName
            , placeholder = Nothing
            , text = simulation.name
            }
        else
          Input.button styles.tab
            { onPress = Just <| ChangeActiveSimulation simulation
            , label = E.el [ E.padding 15, E.inFront <| viewCloseTabButton simulation, E.alignLeft ] <| E.text simulation.name
            }
      )
      model.simulations
    ++ [ viewAddTab ]


viewCloseTabButton : Simulation.Model -> E.Element Msg
viewCloseTabButton target =
  Input.button
    [ E.mouseOver
      [ Background.color colors.lightGrey ]
    , E.paddingXY 3 3
    , E.centerY, E.alignRight
    , Border.rounded 10
    ]
    { onPress =
      Just <| RemoveSimulation target
    , label =
      centeredText "x"
    }


viewAddTab : E.Element Msg
viewAddTab =
  Input.button (styles.button ++ [ E.width <| E.px 20, Border.rounded 20 ])
    { onPress =
      Just AddSimulation
    , label =
      centeredText "+"
    }


update : Msg -> Model -> (Model, Cmd Msg)
update message model =
  case message of
    UpdateActiveSimulationName newName ->
      (updateActiveSimulationName newName model, Cmd.none)

    ChangeActiveSimulation newSimulation ->
      (changeActiveSimulation newSimulation model, Cmd.none)

    SimulationMsg msg ->
      updateActiveSimulationWithMsg msg model

    AddSimulation ->
      addSimulation model

    RemoveSimulation target ->
      (removeSimulation target model, Cmd.none)

    SaveProject ->
      ( model
      , saveProject <| encodeProject model
      )

    ShowPopUp popUp ->
      (showPopUp popUp model, Cmd.none)

    UpdatePendingSetting field value ->
      ( updatePendingSetting field value model, Cmd.none)

    ApplyPendingSettings ->
      ( applyPendingSettings model, Cmd.none)

    ApplySettingsToFutureFields ->
      (applySettingsToFutureFields model, Cmd.none)

    ApplySettingsToCurrentAndFutureFields ->
      applySettingsToCurrentAndFutureFields model

    CloseSettingsPopUp ->
      (closeSettingsPopUp model, Cmd.none)

    CloseHelpPopUp ->
      (closeHelpPopUp model, Cmd.none)

    DownloadModelAsSvg ->
      ( closeDownloadPopUp model
      , downloadModelAsSvg model.activeSimulation.name
      )

    DownloadModelAsJson ->
      ( closeDownloadPopUp model
      , File.Download.string model.activeSimulation.name "application/json" (Encode.encode 2 <| Simulation.encodeModel model.activeSimulation)
      )

    CloseDownloadPopUp ->
      ( closeDownloadPopUp model, Cmd.none)

    JsonRequested ->
      ( model, File.Select.file ["application/json"] JsonSelected)

    JsonSelected file ->
      ( model, Task.perform JsonLoaded (File.toString file))

    JsonLoaded jsonString ->
      (loadSimulation jsonString model, Cmd.none)

    CloseUploadPopUp ->
      ( closeUploadPopUp model, Cmd.none)

    GotViewport viewport ->
      updateSimulationSize (viewport.viewport.width - 50) (viewport.viewport.height - 110) model

    WindowResized newWidth newHeight ->
      updateSimulationSize (toFloat newWidth - 50) (toFloat newHeight - 110) model

    ToggleShowSourceValue newChecked ->
      toggleShowSourceValue newChecked model

    PickSimulationColors part msg ->
      pickSimulationColors part msg model

    UpdateActiveSimulationState ->
      (updateActiveSimulationState model, Cmd.none)

    DoNothing ->
      (model, Cmd.none)


updateActiveSimulationName : String -> Model -> Model
updateActiveSimulationName newName model =
  let
    oldActiveSimulation =
      model.activeSimulation
    newActiveSimulation =
      { oldActiveSimulation
        | name =
          if newName == "" then
            getDefaultSimulationName model.defaultSimulationIndex
          else
            newName
      }
  in
  updateActiveSimulation newActiveSimulation model


getDefaultSimulationName : Int -> String
getDefaultSimulationName index =
  Simulation.defaultName ++ " " ++ String.fromInt index


changeActiveSimulation : Simulation.Model -> Model -> Model
changeActiveSimulation newSimulation model =
  { model
    | activeSimulation =
      newSimulation
  }


updateActiveSimulationWithMsg : Simulation.Msg -> Model -> (Model, Cmd Msg)
updateActiveSimulationWithMsg msg model =
  let
    (newSimulation, cmd) =
      Simulation.update msg model.activeSimulation
  in
  ( updateActiveSimulation newSimulation model
  , Cmd.map SimulationMsg cmd
  )


updateActiveSimulation : Simulation.Model -> Model -> Model
updateActiveSimulation newActiveSimulation model =
  { model
  | activeSimulation =
    newActiveSimulation
  , simulations =
      List.map
        (\simulation ->
          if simulation == model.activeSimulation then
            newActiveSimulation
          else
            simulation
        )
      model.simulations
  }


mapActiveSimulation : (Simulation.Model -> Simulation.Model) -> Model -> Model
mapActiveSimulation func model =
  let
    mappedActiveSimulation =
      func model.activeSimulation
  in
  { model
  | activeSimulation =
    mappedActiveSimulation
  , simulations =
      List.map
        (\simulation ->
          if simulation == model.activeSimulation then
            mappedActiveSimulation
          else
            simulation
        )
      model.simulations
  } 


addSimulation : Model -> (Model, Cmd Msg)
addSimulation model =
  let
    newDefaultSimulationIndex =
      model.defaultSimulationIndex + 1

    defaultSimulationName =
      getDefaultSimulationName <| newDefaultSimulationIndex
    
    (simulation, simulationCmd) =
      Simulation.init model.simulationWidth model.simulationHeight

    newSimulation =
      { simulation
        | name =
          defaultSimulationName
      }
  in
  ({ model
    | simulations =
      model.simulations ++ [ newSimulation ]
    , activeSimulation =
      newSimulation
    , defaultSimulationIndex =
      newDefaultSimulationIndex
  }
  , Cmd.map SimulationMsg simulationCmd
  )


removeSimulation : Simulation.Model -> Model -> Model
removeSimulation target model =
  if List.length model.simulations == 1 then
    model
  else
    let
      updatedSimulations =
        List.filter
          (\simulation ->
            simulation /= target
          )
          model.simulations
      updatedModel =
        { model
          | simulations =
            updatedSimulations
          , defaultSimulationIndex =
            if String.startsWith Simulation.defaultName target.name then
              model.defaultSimulationIndex - 1
            else
              model.defaultSimulationIndex
        }
    in
    if target == model.activeSimulation then
      { updatedModel
        | activeSimulation =
          getNextSimulation target model.simulations
      }
    else
      updatedModel


getNextSimulation : Simulation.Model -> List Simulation.Model -> Simulation.Model
getNextSimulation current simulations =
  let
    splits =
      List.Extra.splitWhen ((==) current) simulations
    next =
      case splits of
        Just (firstToPrevious, currentToLast) ->
          if List.length currentToLast == 1 then -- current is the last simulation
            -- try getting the previous simulation
            Maybe.withDefault current <| List.Extra.last <| firstToPrevious
          else
          -- try getting the next simulation
            Maybe.withDefault current <| List.head <| List.Extra.removeAt 0 currentToLast
        Nothing ->
          current -- impossible
  in
  next


viewControlPanel : Model -> E.Element Msg
viewControlPanel model =
  E.row
    [ E.centerX
    , E.spacing 10
    , styles.padTop10
    ]
    [ viewButtonNoProp "Help" <| ShowPopUp HelpPopUp
    , viewButtonNoProp "Settings" <| ShowPopUp SettingsPopUp
    , viewUpdateStateButton model
    , viewButtonNoProp "Download" <| ShowPopUp DownloadPopUp
    , viewButtonNoProp "Upload" <| ShowPopUp UploadPopUp
    ]


viewUpdateStateButton : Model -> E.Element Msg
viewUpdateStateButton model =
  Input.button styles.button
    { onPress =
      Just UpdateActiveSimulationState
    , label =
        E.html <| case model.activeSimulation.state of
          Simulation.Running ->
            FeatherIcons.pause
              |> FeatherIcons.toHtml []
          Simulation.Resting ->
            FeatherIcons.play
              |> FeatherIcons.toHtml []
    }


viewButtonNoProp : String -> Msg -> E.Element Msg
viewButtonNoProp text msg =
  Input.button (styles.button ++ [
    E.htmlAttribute <| onClickNoProp msg
  ]) <|
    { onPress =
      Nothing
    , label = centeredText text
    }


viewPopUp : Model -> E.Element Msg
viewPopUp model =
  case model.popUp of
    HelpPopUp ->
      viewHelpPopUp
    SettingsPopUp ->
      viewSettingsPopUp model
    ApplyOptionsPopUp ->
      viewApplyOptions model
    DownloadPopUp ->
      viewDownloadPopUp
    UploadPopUp ->
      viewUploadPopUp model
    NoPopUp ->
      E.none


viewSettingsPopUp : Model -> E.Element Msg
viewSettingsPopUp model =
  let
    settings =
      model.pendingSettings
  in
  viewPopUpOf "Settings"
    [ E.inFront <| viewApplyOptions model
    , E.scrollbarY
    ]
    [ textHeader "Electric Field Settings"
    , Input.text []
      { onChange = UpdatePendingSetting "r"
       , text = String.fromFloat settings.r
       , placeholder = Nothing
       , label = Input.labelLeft [ E.centerY ] <| E.text "Charge radius (px)"
       }
    , Input.text []
      { onChange = UpdatePendingSetting "density"
       , text = String.fromInt settings.density
       , placeholder = Nothing
       , label = Input.labelLeft [ E.centerY ] <| E.text "Field line density"
       }
    , Input.text []
      { onChange = UpdatePendingSetting "steps"
      , text = String.fromInt settings.steps
      , placeholder = Nothing
      , label = Input.labelLeft [ E.centerY ] <| E.text "Draw steps"
      }
  , Input.text []
    { onChange = UpdatePendingSetting "delta"
    , text = String.fromFloat settings.delta
    , placeholder = Nothing
    , label = Input.labelLeft [ E.centerY ] <| E.text "Draw step size (px)"
    }
  , Input.text []
    { onChange = UpdatePendingSetting "magnitude"
    , text = String.fromFloat settings.magnitude
    , placeholder = Nothing
    , label = Input.labelLeft [ E.centerY ] <| E.text "Charge magnitude"
    }
  , E.row
    [ E.width E.fill
    , styles.padTop20
    ]
    [ Input.button (styles.button ++ [E.alignLeft])
      { onPress =
        Just ApplyPendingSettings
      , label =
        centeredText "Apply"
      }
      , Input.button (styles.button ++ [E.alignRight])
      { onPress =
        Just CloseSettingsPopUp
      , label =
        centeredText "Cancel"
      }
    ]
  , textHeader "Global Settings"
  , E.text "Global settings are immediately applied to all electric fields."
  , Input.checkbox []
    { onChange = ToggleShowSourceValue
    , icon = Input.defaultCheckbox
    , checked = settings.showSourceValue
    , label =
        Input.labelRight [] <|
          E.text "Show source charge's value"
    }
  , E.text "Pick colors for:"
  , E.row
    [ E.spacing 20 ]
    [ E.column []
      [ E.text "Positive charges"
      , E.html <| (ColorPicker.view settings.colors.positiveCharge model.positiveChargeColorPicker
        |> Html.map (PickSimulationColors "positiveCharge"))
      ]
    , E.column []
      [ E.text "Positive field lines"
      , E.html <| (ColorPicker.view settings.colors.positiveLine model.positiveLineColorPicker
        |> Html.map (PickSimulationColors "positiveLine"))
      ]
    ]
  , E.row
    [ E.spacing 20 ]
    [ E.column []
      [ E.text "Negative charges"
      , E.html <| (ColorPicker.view settings.colors.negativeCharge model.negativeChargeColorPicker
        |> Html.map (PickSimulationColors "negativeCharge"))
      ]
    , E.column []
      [ E.text "Negative field lines"
      , E.html <| (ColorPicker.view settings.colors.negativeLine model.negativeLineColorPicker
        |> Html.map (PickSimulationColors "negativeLine"))
      ]
    ]
  , E.column []
    [ E.text "Background"
    , E.html <| (ColorPicker.view settings.colors.background model.backgroundColorPicker
      |> Html.map (PickSimulationColors "background"))
    ]
  , E.el [ styles.padTop20, E.alignRight ] <|
      Input.button
        styles.button
        { onPress = Just CloseSettingsPopUp
        , label = centeredText "Close"
        }
  ]


viewApplyOptions : Model -> E.Element Msg
viewApplyOptions model =
  case model.popUp of
    ApplyOptionsPopUp ->
      viewPopUpOf "Which fields do you want to apply to?" []
        [ Input.button
          (styles.button ++ [ E.width <| E.fill ] )
          { onPress = Just ApplySettingsToFutureFields
          , label = centeredText "Apply to future fields"
          }
        , Input.button
          (styles.button ++ [ E.width <| E.fill ] )
          { onPress = Just ApplySettingsToCurrentAndFutureFields
          , label = centeredText "Apply to current and future fields"
          }
        ]
    _ ->
      E.none


viewHelpPopUp : E.Element Msg
viewHelpPopUp =
  viewPopUpOf "Help" []
    [ textHeader "When you mouse over a charge and ..."
    , E.text "  Single click: select charge"
    , E.text "  Double click: negate charge"
    , E.text "  Right click:  * delete charge"
    , E.text "                * duplicate charge"
    , E.text "                * deselect charge"
    , E.text "  Scroll up:    increase charge magnitude"
    , E.text "  Scroll down:  decrease charge magnitude"
    , textHeader "When you mouse over background and ..."
    , E.text "  Right Click:  * add + charge"
    , E.text "                * add - charge"
    , E.el [ styles.padTop20, E.alignRight ] <|
      Input.button
        styles.button
        { onPress = Just CloseHelpPopUp
        , label = centeredText "Close"
        }
      ]


viewDownloadPopUp : E.Element Msg
viewDownloadPopUp =
  viewPopUpOf "Download" [ E.spacing 12 ]
    [ textHeader "Which format do you want to download in?"
    , E.text "Pick SVG if you want to share or display the model."
    , Input.button
        (styles.button ++ [ E.width <| E.fill ] )
        { onPress = Just DownloadModelAsSvg
        , label = centeredText "Download as SVG"
        }
    , E.text "Pick JSON if you want to save the model for editing later."
    , Input.button
      (styles.button ++ [ E.width <| E.fill ] )
      { onPress = Just DownloadModelAsJson
      , label = centeredText "Downloas as JSON"
      }
    , E.el
      [ styles.padTop20
      , E.alignRight
      ] <|
      Input.button styles.button
      { onPress =
        Just CloseDownloadPopUp
      , label =
        centeredText "Cancel"
      }
    ]


viewUploadPopUp : Model -> E.Element Msg
viewUploadPopUp model =
  viewPopUpOf "Upload" [ E.spacing 12 ]
    [ textHeader "Load a simulation from a local JSON file."
    , Input.button
      (styles.button ++ [ E.width <| E.fill ] )
      { onPress = Just JsonRequested
      , label = centeredText "Upload from my computer"
      }
    , case model.uploadResult of
      UploadSuccess ->
        E.text "Upload succeeds!"
      UploadFailure error ->
        E.html <|
          Html.pre []
            [ Html.text
              ( Decode.errorToString error
                |> String.replace "\\\"" "\""
                |> String.replace "\\n" "\n"
              )
            ]
      UploadPending ->
        E.none
    , Input.button (styles.button ++ [ styles.padTop20, E.alignRight])
      { onPress =
        Just CloseUploadPopUp
      , label =
        centeredText "Close"
      }
    ]


viewPopUpOf : String -> List (E.Attribute Msg) -> List (E.Element Msg) -> E.Element Msg
viewPopUpOf title attributes content =
  E.column
    ([ E.centerX
    , E.centerY
    , E.padding 20
    , E.spacing 6
    , Background.color <| colors.lightGrey
    , Border.width 2
    , Border.color <| colors.black
    , E.htmlAttribute <| onClickNoProp DoNothing
    ] ++ attributes) <|
    [ E.el
      [ Font.size 18
      , E.paddingEach
        { left = 0
        , right = 0
        , top = 0
        , bottom = 10
        }
      ] <|
      E.text title
    ] ++ content


textHeader : String -> E.Element Msg
textHeader text =
  E.el
    [ styles.padTop20
    , Font.bold
    ] <|
    E.text text


onClickNoProp : Msg -> Html.Attribute Msg
onClickNoProp msg =
  Html.Events.custom "click"
    (Decode.succeed
    { message = msg
    , stopPropagation = True
    , preventDefault = False
    }
  )

closeDownloadPopUp : Model -> Model
closeDownloadPopUp model =
  { model
    | popUp =
      NoPopUp
  }


loadSimulation : String -> Model -> Model
loadSimulation jsonString model =
  case Decode.decodeString Simulation.decodeModel jsonString of
    Ok uploadedSimulation ->
      { model
        | uploadResult =
          UploadSuccess
        , simulations =
          model.simulations ++ [ uploadedSimulation ]
        , activeSimulation =
          uploadedSimulation
      }
    Err err ->
      { model
        | uploadResult =
          UploadFailure err
      }
          

closeUploadPopUp : Model -> Model
closeUploadPopUp model =
  { model
    | popUp =
      NoPopUp
    , uploadResult =
      UploadPending
  }


closeHelpPopUp : Model -> Model
closeHelpPopUp model =
  { model
    | popUp =
      NoPopUp
  }


closeSettingsPopUp : Model -> Model
closeSettingsPopUp model =
  { model
    | popUp =
      NoPopUp
    , pendingSettings =
      model.activeSimulation.settings
  }


applyPendingSettings : Model -> Model
applyPendingSettings model =
  { model
    | popUp =
      ApplyOptionsPopUp
  }


applySettingsToFutureFields : Model -> Model
applySettingsToFutureFields model =
  let
    updatedModel =
      mapActiveSimulation
        (\simulation ->
          { simulation
            | settings =
              model.pendingSettings
          }
        )
        model
  in
  { updatedModel
    | popUp =
      NoPopUp
  }


applySettingsToCurrentAndFutureFields : Model -> (Model, Cmd Msg)
applySettingsToCurrentAndFutureFields model =
  let
    newSettings =
      model.pendingSettings
    newFields =
      List.map
        (\field ->
          let
            source =
              field.source
          in
          { field
            | source =
              { source
                | r = newSettings.r
                , magnitude = newSettings.magnitude
              }
            , density =
              newSettings.density
            , steps =
              newSettings.steps
            , delta =
              newSettings.delta
          }
        )
        model.activeSimulation.fields
    updatedModel =
      mapActiveSimulation
      (\simulation ->
        { simulation
          | settings =
            newSettings
        }
      )
      model

  in
  ({ updatedModel
    | popUp =
      NoPopUp
  }
  , Simulation.calculateFields updatedModel.activeSimulation.width updatedModel.activeSimulation.height newFields
  )


updatePendingSetting : String -> String -> Model -> Model
updatePendingSetting field value model =
  let
    settings =
      model.pendingSettings
    newSettings =
      case field of
        "r" ->
          case String.toFloat value of
            Just v -> { settings | r = v }
            Nothing -> settings
        "density" ->
          case String.toInt value of
            Just v -> { settings | density = v }
            Nothing -> settings
        "steps" ->
          case String.toInt value of
            Just v -> { settings | steps = v }
            Nothing -> settings
        "delta" ->
          case String.toFloat value of
            Just v -> { settings | delta = v }
            Nothing -> settings
        "magnitude" ->
          case String.toFloat value of
            Just v -> { settings | magnitude = v }
            Nothing -> settings
        _ ->
          settings
  in
  { model |
    pendingSettings =
      newSettings
  }


showPopUp : PopUp -> Model -> Model
showPopUp popUp model =
  { model |
    popUp =
      popUp
  }


updateSimulationSize : Float -> Float -> Model -> (Model, Cmd Msg)
updateSimulationSize newWidth newHeight model =
  let
    updateSize =
      \simulation ->
        if simulation.width /= newWidth || simulation.height /= newHeight then
          Simulation.init newWidth newHeight
        else
          (simulation, Cmd.none)
    (newSimulations, newSimulationCmds) =
      List.unzip <|
        List.map
          updateSize
          model.simulations
    (newActiveSimulation, _) =
      updateSize model.activeSimulation
  in
  ({ model
    | simulationWidth =
      newWidth
    , simulationHeight =
      newHeight
    , simulations =
      newSimulations
    , activeSimulation =
      newActiveSimulation
  }
  , Cmd.batch (List.map (Cmd.map SimulationMsg) newSimulationCmds)
  )


toggleShowSourceValue : Bool -> Model -> (Model, Cmd Msg)
toggleShowSourceValue newChecked model =
  updateGlobalSettings
    (\settings ->
      { settings
        | showSourceValue =
          newChecked
      }
    )
    model


pickSimulationColors : String -> ColorPicker.Msg -> Model -> (Model, Cmd Msg)
pickSimulationColors part msg model =
  let
    oldColors =
      model.pendingSettings.colors
    (oldColor, oldColorPicker) =
      case part of
        "positiveCharge" ->
          (oldColors.positiveCharge, model.positiveChargeColorPicker)
        "negativeCharge" ->
          (oldColors.negativeCharge, model.negativeChargeColorPicker)
        "positiveLine" ->
          (oldColors.positiveLine, model.positiveLineColorPicker)
        "negativeLine" ->
          (oldColors.negativeLine, model.negativeLineColorPicker)
        "background" ->
          (oldColors.background, model.backgroundColorPicker)
        _ ->
          (Color.black, model.positiveChargeColorPicker) -- impossible
    ( newColorPicker, newMaybeColor ) =
      ColorPicker.update msg oldColor oldColorPicker
    newColor =
      Maybe.withDefault oldColor <| newMaybeColor
    updatedModel =
      case part of
        "positiveCharge" ->
          { model | positiveChargeColorPicker = newColorPicker }
        "negativeCharge" ->
          { model | negativeChargeColorPicker = newColorPicker }
        "positiveLine" ->
          { model | positiveLineColorPicker = newColorPicker }
        "negativeLine" ->
          { model | negativeLineColorPicker = newColorPicker }
        "background" ->
          { model | backgroundColorPicker = newColorPicker }
        _ ->
          model
  in
  updateGlobalSettings
    (\settings ->
      let
        colors =
          settings.colors
      in
      { settings
        | colors =
            case part of
              "positiveCharge" ->
                { colors | positiveCharge = newColor}
              "negativeCharge" ->
                { colors | negativeCharge = newColor }
              "positiveLine" ->
                { colors | positiveLine = newColor }
              "negativeLine" ->
                { colors | negativeLine = newColor }
              "background" ->
                { colors | background = newColor }
              _ ->
                colors
      }
    )
    updatedModel


updateActiveSimulationState : Model -> Model
updateActiveSimulationState model =
  let
    activeSimulation =
      model.activeSimulation
    nextState =
      case activeSimulation.state of
        Simulation.Running ->
          Simulation.Resting
        Simulation.Resting ->
          Simulation.Running
  in
  { model
    | activeSimulation =
      { activeSimulation
        | state =
          nextState
      }
  }


updateGlobalSettings : (Simulation.Settings -> Simulation.Settings) -> Model -> (Model, Cmd Msg)
updateGlobalSettings func model =
  let
    settings =
      model.activeSimulation.settings
    updatedSettings =
      func settings
    (updatedModel, modelCmd) =
      applySettingsToCurrentAndFutureFields
      { model
        | pendingSettings =
          updatedSettings
      }
  in
  ({ updatedModel
    | popUp =
      SettingsPopUp
  }
  , modelCmd
  )



encodeProject : Model -> Encode.Value
encodeProject model =
  Encode.object
    [ ("simulations", Encode.list Simulation.encodeModel model.simulations)
    , ("activeSimulation", Simulation.encodeModel model.activeSimulation)
    , ("defaultSimulationIndex", Encode.int model.defaultSimulationIndex)
    ]



decodeProject : Decoder Model
decodeProject =
  Field.require "simulations" (Decode.list Simulation.decodeModel) <| \simulations ->
  Field.require "activeSimulation" Simulation.decodeModel <| \activeSimulation ->
  Field.require "defaultSimulationIndex" Decode.int <| \defaultSimulationIndex ->

  Decode.succeed
    { simulations = simulations
    , activeSimulation = activeSimulation
    , defaultSimulationIndex = defaultSimulationIndex
    , uploadResult = UploadPending
    , popUp = NoPopUp
    , pendingSettings = Simulation.defaultSettings
    , simulationWidth = defaultSimulationWidth
    , simulationHeight = defaultSimulationHeight
    , positiveChargeColorPicker = ColorPicker.empty
    , positiveLineColorPicker = ColorPicker.empty
    , negativeChargeColorPicker = ColorPicker.empty
    , negativeLineColorPicker = ColorPicker.empty
    , backgroundColorPicker = ColorPicker.empty
    }


subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
    [ Sub.map SimulationMsg <| Simulation.subscriptions model.activeSimulation
    , pageWillClose (\_ -> SaveProject)
    , Browser.Events.onResize WindowResized
    ]

  
main : Program (Maybe String) Model Msg
main =
  Browser.element
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }