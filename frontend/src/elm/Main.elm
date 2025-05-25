module Main exposing
    ( Msg(..)
    , init
    , main
    , subscriptions
    , update
    , view
    )

import Auth
import Browser
import Browser.Navigation as Nav
import Dict
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Encode exposing (Value)
import Login
import Pages
import Platform.Cmd as Cmd
import Router
import State
import Toast exposing (withAttributes, withTrayAttributes)
import Updaters
import Url
import ViewUtil exposing (svgIcon)


type alias Model =
    { key : Nav.Key
    , url : Url.Url
    , page : Router.Target
    , pages : Pages.Models
    , creds : Auth.Cred
    , toastTray : Toast.Tray Toast
    }


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | PathRequested String
    | SignOut
    | StoreChange ( String, Value )
    | PageMsg Pages.Msg
    | ToastMsg Toast.Msg
    | CloseToast (Toast.Info ())


type Toast
    = MainToast ToastContent
    | PageToast Pages.Toast


type ToastContent
    = Tester


main : Program Value Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }


init : Value -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    let
        ( startingTray, toastCmd ) =
            Toast.persistent (MainToast Tester)
                |> Toast.withExitTransition 500
                |> Toast.addUnique Toast.tray

        baseModel =
            Model
                key
                { url | path = "/" }
                Router.Landing
                Pages.init
                Auth.unauthenticated
                startingTray

        fromStore =
            State.loadAll flags

        model =
            Dict.foldl loadIntoModel baseModel fromStore
    in
    routeToPage url model
        |> Tuple.mapSecond (\c -> Cmd.batch [ c, Cmd.map ToastMsg toastCmd ])


type alias Updater model msg =
    model -> ( model, Cmd msg )



-- [ requestUpdatePath (\m -> Router.WhatShouldWePlay m.nick.eventId (Just newsort)) ]


onNav : Router.Target -> Updater Model Msg
onNav target model =
    ( model
    , Nav.pushUrl model.key (Router.buildFromTarget target)
    )


onUpdatePage : Router.Target -> Updater Model Msg
onUpdatePage target model =
    ( model
    , Nav.replaceUrl model.key (Router.buildFromTarget target)
    )


onNewCred : Auth.Cred -> Updater Model Msg
onNewCred newcred model =
    ( { model | creds = newcred }
    , Auth.storeCred newcred
    )


onAddToast : Toast -> Updater Model Msg
onAddToast toast model =
    let
        ( newTray, msg ) =
            Toast.addUnique model.toastTray
                (Toast.persistent toast
                    |> Toast.withExitTransition 500
                )
    in
    ( { model | toastTray = newTray }
    , Cmd.map ToastMsg msg
    )


childUpdate : Updater Pages.Models Pages.Msg -> Updater Model Msg
childUpdate =
    Updaters.childUpdate .pages (\model -> \pagemodel -> { model | pages = pagemodel }) PageMsg


handleToastMsg : Toast.Msg -> Updater Model Msg
handleToastMsg msg model =
    let
        ( tray, newTmesg ) =
            Toast.update msg model.toastTray
    in
    ( { model | toastTray = tray }, Cmd.map ToastMsg newTmesg )


closeToast : Toast.Info () -> Updater Model Msg
closeToast info model =
    handleToastMsg (Toast.exit info.id) model


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        interface =
            { requestNav = onNav
            , requestUpdatePath = onUpdatePage
            , sendToast = PageToast >> onAddToast
            , installNewCred = onNewCred
            , lowerModel = .pages
            , localUpdate = childUpdate
            }
    in
    case msg of
        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    let
                        parse =
                            Url.fromString href
                    in
                    case parse of
                        Nothing ->
                            Debug.log "elm passed empty href, wtf?" ( model, Cmd.none )

                        Just _ ->
                            ( model, Nav.load href )

        PathRequested path ->
            ( model, Nav.pushUrl model.key path )

        StoreChange ( key, value ) ->
            ( loadIntoModel key value model, Cmd.none )

        SignOut ->
            ( { model | creds = Auth.unauthenticated }, Cmd.map PageMsg (Cmd.map Pages.LoginMsg (Login.logout model.creds)) )

        UrlChanged url ->
            routeToPage url model

        PageMsg submsg ->
            Updaters.compose (Pages.updaters interface submsg) model

        ToastMsg submsg ->
            handleToastMsg submsg model

        CloseToast info ->
            closeToast info model


loadIntoModel : String -> Value -> Model -> Model
loadIntoModel key value model =
    case State.asString value of
        Just s ->
            -- add an if clause for each storage field
            if key == Auth.storageField then
                { model | creds = Auth.loadCred s }

            else
                model

        Nothing ->
            model


routeToPage : Url.Url -> Model -> ( Model, Cmd Msg )
routeToPage url model =
    case ( Debug.log "model.url.path" model.url.path == Debug.log "url.path" url.path, Router.routeToTarget url ) of
        -- If we route to the same page again, do nothing
        -- Debatable: query params might be significant, and only the page can know that
        -- XXX therefore, consider adding a Pages.queryUpdate to handle that case
        ( True, Just target ) ->
            Debug.log "just updating page url" ( { model | page = target }, Cmd.none )

        ( False, Just target ) ->
            let
                interface =
                    { requestNav = onNav
                    , requestUpdatePath = onUpdatePage
                    , installNewCred = onNewCred
                    , lowerModel = .pages
                    , localUpdate = childUpdate
                    , sendToast = PageToast >> onAddToast
                    }

                submsg =
                    Pages.pageNavMsg target model.creds
            in
            Updaters.compose (Pages.updaters interface submsg) { model | page = target }

        ( _, Nothing ) ->
            ( model, Nav.pushUrl model.key "/" )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    State.onStoreChange StoreChange



-- VIEW


view : Model -> Browser.Document Msg
view model =
    let
        wrapMsg =
            List.map (Html.map PageMsg)
    in
    { title = "Wag The Pig"
    , body =
        [ div [ class "page", class (Router.pageName model.page) ]
            (nav []
                [ a [ href (Router.buildFromTarget Router.Landing) ]
                    [ img [ src "/assets/wagthepig-med.png" ] []
                    ]
                , ul [ class "menu" ]
                    [ headerButton "Profile" "/profile"
                    , headerButton "Events" "/events"
                    , authButton model
                    ]
                ]
                :: (Pages.view model.page model.pages
                        |> wrapMsg
                   )
                ++ [ Toast.render viewToast model.toastTray toastConfig
                   , div [ class "footer" ]
                        [ a [ href "https://github.com/nyarly/wagthepig" ] [ text "Contribute!" ]
                        , text " "
                        , a [ href "https://github.com/nyarly/wagthepig/issues" ] [ s [] [ text "Complain!" ], text " Suggest!" ]
                        ]
                   ]
            )
        ]
    }


toastConfig : Toast.Config Msg
toastConfig =
    Toast.config ToastMsg
        |> withTrayAttributes [ class "toast-tray" ]
        |> withAttributes [ class "toast" ]
        |> Toast.withEnterAttributes [ class "entering" ]
        |> Toast.withExitAttributes [ class "exiting" ]


viewToast : List (Html.Attribute Msg) -> Toast.Info Toast -> Html Msg
viewToast attributes toastInfo =
    let
        unwrapToast info content =
            Toast.Info info.id info.phase info.interaction content

        wrapHtml =
            List.map (Html.map PageMsg)
    in
    div attributes
        ((case toastInfo.content of
            MainToast Tester ->
                [ text "this is a test toast" ]

            PageToast subToast ->
                Pages.viewToast (unwrapToast toastInfo subToast)
                    |> wrapHtml
         )
            ++ [ button [ class "toast-close", onClick (CloseToast (stripToastInfo toastInfo)) ] [ svgIcon "cross" ] ]
        )


stripToastInfo : Toast.Info c -> Toast.Info ()
stripToastInfo info =
    Toast.Info info.id info.phase info.interaction ()


authButton : Model -> Html Msg
authButton model =
    if Auth.loggedIn model.creds then
        li [] [ button [ class "header", onClick SignOut ] [ text "Sign Out" ] ]

    else
        headerButton "Log In" "/login"


headerButton : String -> String -> Html Msg
headerButton txt path =
    li [] [ button [ class "header", onClick (PathRequested path) ] [ text txt ] ]
