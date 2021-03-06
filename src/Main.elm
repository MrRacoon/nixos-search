module Main exposing (main)

import Browser
import Browser.Navigation
import Html
    exposing
        ( Html
        , a
        , button
        , div
        , footer
        , header
        , img
        , li
        , span
        , text
        , ul
        )
import Html.Attributes
    exposing
        ( attribute
        , class
        , classList
        , href
        , id
        , src
        , type_
        )
import Page.Home
import Page.Options
import Page.Packages
import Route
import Search
import Url
import Url.Builder



-- MODEL


type alias Flags =
    { elasticsearchMappingSchemaVersion : Int
    , elasticsearchUrl : String
    , elasticsearchUsername : String
    , elasticsearchPassword : String
    }


type alias Model =
    { navKey : Browser.Navigation.Key
    , route : Route.Route
    , elasticsearch : Search.Options
    , page : Page
    }


type Page
    = NotFound
    | Home Page.Home.Model
    | Packages Page.Packages.Model
    | Options Page.Options.Model


init :
    Flags
    -> Url.Url
    -> Browser.Navigation.Key
    -> ( Model, Cmd Msg )
init flags url navKey =
    let
        model =
            { navKey = navKey
            , elasticsearch =
                Search.Options
                    flags.elasticsearchMappingSchemaVersion
                    flags.elasticsearchUrl
                    flags.elasticsearchUsername
                    flags.elasticsearchPassword
            , page = NotFound
            , route = Route.Home
            }
    in
    changeRouteTo model url



-- UPDATE


type Msg
    = ChangedUrl Url.Url
    | ClickedLink Browser.UrlRequest
    | HomeMsg Page.Home.Msg
    | PackagesMsg Page.Packages.Msg
    | OptionsMsg Page.Options.Msg


updateWith :
    (subModel -> Page)
    -> (subMsg -> Msg)
    -> Model
    -> ( subModel, Cmd subMsg )
    -> ( Model, Cmd Msg )
updateWith toPage toMsg model ( subModel, subCmd ) =
    ( { model | page = toPage subModel }
    , Cmd.map toMsg subCmd
    )


submitQuery :
    Model
    -> ( Model, Cmd Msg )
    -> ( Model, Cmd Msg )
submitQuery old ( new, cmd ) =
    let
        triggerSearch _ newModel msg makeRequest =
            if
                (newModel.query /= Nothing)
                    && (newModel.query /= Just "")
                    && List.member newModel.channel Search.channels
            then
                ( new
                , Cmd.batch
                    [ cmd
                    , makeRequest
                        new.elasticsearch
                        newModel.channel
                        (Maybe.withDefault "" newModel.query)
                        newModel.from
                        newModel.size
                        newModel.sort
                        |> Cmd.map msg
                    ]
                )

            else
                ( new, cmd )
    in
    case ( old.page, new.page ) of
        ( Packages oldModel, Packages newModel ) ->
            triggerSearch oldModel newModel PackagesMsg Page.Packages.makeRequest

        ( NotFound, Packages newModel ) ->
            triggerSearch newModel newModel PackagesMsg Page.Packages.makeRequest

        ( Options oldModel, Options newModel ) ->
            triggerSearch oldModel newModel OptionsMsg Page.Options.makeRequest

        ( NotFound, Options newModel ) ->
            triggerSearch newModel newModel OptionsMsg Page.Options.makeRequest

        ( _, _ ) ->
            ( new, cmd )


changeRouteTo :
    Model
    -> Url.Url
    -> ( Model, Cmd Msg )
changeRouteTo currentModel url =
    let
        attempteQuery ( newModel, cmd ) =
            let
                -- We intentially throw away Cmd
                -- because we don't want to perform any effects
                -- in this cases where route itself doesn't change
                noEffects =
                    ( newModel, Cmd.none )
            in
            case ( currentModel.route, newModel.route ) of
                ( Route.Packages arg1, Route.Packages arg2 ) ->
                    if
                        (arg1.channel /= arg2.channel)
                            || (arg1.query /= arg2.query)
                            || (arg1.from /= arg2.from)
                            || (arg1.size /= arg2.size)
                            || (arg1.sort /= arg2.sort)
                    then
                        submitQuery newModel ( newModel, cmd )

                    else
                        noEffects

                ( Route.Options arg1, Route.Options arg2 ) ->
                    if
                        (arg1.channel /= arg2.channel)
                            || (arg1.query /= arg2.query)
                            || (arg1.from /= arg2.from)
                            || (arg1.size /= arg2.size)
                            || (arg1.sort /= arg2.sort)
                    then
                        submitQuery newModel ( newModel, cmd )

                    else
                        noEffects

                ( a, b ) ->
                    if a /= b then
                        submitQuery newModel ( newModel, cmd )

                    else
                        noEffects
    in
    case Route.fromUrl url of
        Nothing ->
            ( { currentModel | page = NotFound }
            , Cmd.none
            )

        Just route ->
            let
                model =
                    { currentModel | route = route }
            in
            case route of
                Route.NotFound ->
                    ( { model | page = NotFound }, Cmd.none )

                Route.Home ->
                    -- Always redirect to /packages until we have something to show
                    -- on the home page
                    ( model, Browser.Navigation.pushUrl model.navKey "/packages" )

                Route.Packages searchArgs ->
                    let
                        modelPage =
                            case model.page of
                                Packages x ->
                                    Just x

                                _ ->
                                    Nothing
                    in
                    Page.Packages.init searchArgs modelPage
                        |> updateWith Packages PackagesMsg model
                        |> attempteQuery

                Route.Options searchArgs ->
                    let
                        modelPage =
                            case model.page of
                                Options x ->
                                    Just x

                                _ ->
                                    Nothing
                    in
                    Page.Options.init searchArgs modelPage
                        |> updateWith Options OptionsMsg model
                        |> attempteQuery


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case ( msg, model.page ) of
        ( ClickedLink urlRequest, _ ) ->
            case urlRequest of
                Browser.Internal url ->
                    ( model
                    , Browser.Navigation.pushUrl model.navKey <| Url.toString url
                    )

                Browser.External href ->
                    ( model
                    , Browser.Navigation.load href
                    )

        ( ChangedUrl url, _ ) ->
            changeRouteTo model url

        ( HomeMsg subMsg, Home subModel ) ->
            Page.Home.update subMsg subModel
                |> updateWith Home HomeMsg model

        ( PackagesMsg subMsg, Packages subModel ) ->
            Page.Packages.update model.navKey subMsg subModel
                |> updateWith Packages PackagesMsg model

        ( OptionsMsg subMsg, Options subModel ) ->
            Page.Options.update model.navKey subMsg subModel
                |> updateWith Options OptionsMsg model

        ( _, _ ) ->
            -- Disregard messages that arrived for the wrong page.
            ( model, Cmd.none )



-- VIEW


view :
    Model
    ->
        { title : String
        , body : List (Html Msg)
        }
view model =
    let
        title =
            case model.page of
                Packages _ ->
                    "NixOS Search - Packages"

                Options _ ->
                    "NixOS Search - Options"

                _ ->
                    "NixOS Search"
    in
    { title = title
    , body =
        [ div []
            [ header []
                [ div [ class "navbar navbar-static-top" ]
                    [ div [ class "navbar-inner" ]
                        [ div [ class "container" ]
                            [ button
                                [ type_ "button"
                                , class "btn btn-navbar"
                                , attribute "data-toggle" "collapse"
                                , attribute "data-target" ".nav-collapse"
                                ]
                                [ span [ class "icon-bar" ] []
                                , span [ class "icon-bar" ] []
                                , span [ class "icon-bar" ] []
                                ]
                            , a [ class "brand", href "https://nixos.org" ]
                                [ img [ src "https://nixos.org/logo/nix-wiki.png", class "logo" ] []
                                ]
                            , div [ class "nav-collapse collapse" ]
                                [ ul [ class "nav pull-left" ]
                                    (viewNavigation model.route)
                                ]
                            ]
                        ]
                    ]
                ]
            , div [ class "container main" ]
                [ div [ id "content" ] [ viewPage model ]
                , footer
                    [ class "container text-center" ]
                    [ div []
                        [ span [] [ text "Please help us improve the search by " ]
                        , a
                            [ href "https://github.com/NixOS/nixos-search/issues"
                            ]
                            [ text "reporting issues" ]
                        , span [] [ text "." ]
                        ]
                    , div []
                        [ span [] [ text "❤️  " ]
                        , span [] [ text "Elasticsearch instance graciously provided by " ]
                        , a [ href "https://bonsai.io" ] [ text "Bonsai" ]
                        , span [] [ text ". Thank you! ❤️ " ]
                        ]
                    ]
                ]
            ]
        ]
    }


viewNavigation : Route.Route -> List (Html Msg)
viewNavigation route =
    let
        toRoute f =
            case route of
                -- Preserve arguments
                Route.Packages searchArgs ->
                    f searchArgs

                Route.Options searchArgs ->
                    f searchArgs

                _ ->
                    f <| Route.SearchArgs Nothing Nothing Nothing Nothing Nothing Nothing
    in
    li [] [ a [ href "https://nixos.org" ] [ text "Back to nixos.org" ] ]
        :: List.map
            (viewNavigationItem route)
            [ ( toRoute Route.Packages, "Packages" )
            , ( toRoute Route.Options, "Options" )
            ]


viewNavigationItem :
    Route.Route
    -> ( Route.Route, String )
    -> Html Msg
viewNavigationItem currentRoute ( route, title ) =
    li
        [ classList [ ( "active", currentRoute == route ) ] ]
        [ a [ Route.href route ] [ text title ] ]


viewPage : Model -> Html Msg
viewPage model =
    case model.page of
        NotFound ->
            div [] [ text "Not Found" ]

        Home _ ->
            div [] [ text "Welcome" ]

        Packages packagesModel ->
            Html.map (\m -> PackagesMsg m) <| Page.Packages.view packagesModel

        Options optionsModel ->
            Html.map (\m -> OptionsMsg m) <| Page.Options.view optionsModel



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- MAIN


main : Program Flags Model Msg
main =
    Browser.application
        { init = init
        , onUrlRequest = ClickedLink
        , onUrlChange = ChangedUrl
        , subscriptions = subscriptions
        , update = update
        , view = view
        }
