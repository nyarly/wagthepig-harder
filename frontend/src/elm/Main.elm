module Main exposing
    ( Msg(..)
    , main
    )

import Auth
import Browser
import Browser.Navigation as Nav
import Dict
import Html exposing (Html, a, button, div, img, li, nav, p, s, text, ul)
import Html.Attributes exposing (class, href, src)
import Html.Events exposing (onClick)
import Http exposing (Error(..))
import Hypermedia exposing (Error)
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
    | Relogin (Toast.Info ())


type Toast
    = MainToast ToastContent
    | PageToast Pages.Toast


type ToastContent
    = Tester
    | NotAuthorized
    | CouldRetry
    | Unknown


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
        {-
           There has to be a better way to do this:
              ( startingTray, toastCmd ) =
                  Toast.persistent (MainToast Tester)
                      |> Toast.withExitTransition 500
                      |> Toast.addUnique Toast.tray

              ...

             |> Tuple.mapSecond (\c -> Cmd.batch [ c, Cmd.map ToastMsg toastCmd ])
        -}
        startingTray : Toast.Tray content
        startingTray =
            Toast.tray

        baseModel : Model
        baseModel =
            Model
                key
                { url | path = "/" }
                Router.Landing
                Pages.init
                Auth.unauthenticated
                startingTray

        fromStore : Dict.Dict String Value
        fromStore =
            State.loadAll flags

        model : Model
        model =
            Dict.foldl loadIntoModel baseModel fromStore
    in
    routeToPage url model


type alias Updater model msg =
    model -> ( model, Cmd msg )


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


afterLogin : Router.Target -> Updater Model Msg
afterLogin target =
    Pages.afterLoginUpdater interface target


loginSavePoint : Updater Model Msg
loginSavePoint model =
    afterLogin model.page model



-- This should probably clear the credentials
-- but: a) we're about to replace them
-- and  b) they're stashed at each page
-- for the future, this is a strong argument for a single extensible model


saveCurrentPageAndReLogin : Updater Model Msg
saveCurrentPageAndReLogin =
    Updaters.composeList
        [ loginSavePoint
        , onNav Router.Login
        ]


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
                    |> Toast.withExitTransition 100
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


interface :
    { requestNav : Router.Target -> Model -> ( Model, Cmd Msg )
    , requestUpdatePath : Router.Target -> Model -> ( Model, Cmd Msg )
    , sendToast : Pages.Toast -> Model -> ( Model, Cmd Msg )
    , installNewCred : Auth.Cred -> Model -> ( Model, Cmd Msg )
    , lowerModel : { a | pages : b } -> b
    , localUpdate : Updater Pages.Models Pages.Msg -> Model -> ( Model, Cmd Msg )
    , relogin : Updater Model Msg
    , handleError : Error -> Updater Model Msg
    , handleErrorWithRetry : Updater Model Msg -> Error -> Updater Model Msg
    }
interface =
    { requestNav = onNav
    , requestUpdatePath = onUpdatePage
    , sendToast = PageToast >> onAddToast
    , installNewCred = onNewCred
    , lowerModel = .pages
    , localUpdate = childUpdate
    , relogin = saveCurrentPageAndReLogin
    , handleError = handleError
    , handleErrorWithRetry = handleErrorWithRetry
    }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
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
                            ( model, Cmd.none )

                        Just _ ->
                            ( model, Nav.load href )

        PathRequested path ->
            ( model, Nav.pushUrl model.key path )

        StoreChange ( key, value ) ->
            ( loadIntoModel key value model, Cmd.none )

        SignOut ->
            ( { model | creds = Auth.unauthenticated }
            , Cmd.batch
                [ Cmd.map PageMsg (Cmd.map Pages.LoginMsg (Login.logout model.creds))
                , Nav.pushUrl model.key (Router.buildFromTarget Router.Landing)
                ]
            )

        UrlChanged url ->
            routeToPage url model

        PageMsg submsg ->
            Pages.updaters interface submsg model

        ToastMsg submsg ->
            handleToastMsg submsg model

        CloseToast info ->
            closeToast info model

        Relogin info ->
            Updaters.compose
                (closeToast info)
                saveCurrentPageAndReLogin
                model


handleError : Error -> Updater Model Msg
handleError =
    handleErrorWithRetry (onAddToast (MainToast CouldRetry))


handleErrorWithRetry : Updater Model Msg -> Error -> Updater Model Msg
handleErrorWithRetry retry err model =
    case err of
        Timeout ->
            retry model

        NetworkError ->
            retry model

        BadUrl _ ->
            onAddToast (MainToast Unknown) model

        BadStatus status ->
            case status of
                401 ->
                    onAddToast (MainToast NotAuthorized) model

                403 ->
                    onAddToast (MainToast NotAuthorized) model

                429 ->
                    retry model

                _ ->
                    onAddToast (MainToast Unknown) model

        BadBody _ ->
            onAddToast (MainToast Unknown) model


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
    case ( model.url.path == url.path, Router.routeToTarget url, Auth.loggedIn model.creds ) of
        -- If we route to the same page again, do nothing
        -- Debatable: query params might be significant, and only the page can know that
        -- XXX therefore, consider adding a Pages.queryUpdate to handle that case
        ( _, Just Router.Landing, True ) ->
            ( model
            , Nav.pushUrl model.key (Router.buildFromTarget (Router.Events Nothing))
            )

        ( True, Just target, _ ) ->
            ( { model | page = target }, Cmd.none )

        ( False, Just target, _ ) ->
            let
                submsg : Pages.Msg
                submsg =
                    Pages.pageNavMsg target model.creds
            in
            Pages.updaters interface submsg { model | page = target }

        ( _, Nothing, _ ) ->
            ( model, Nav.pushUrl model.key "/" )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    State.onStoreChange StoreChange



-- VIEW


view : Model -> Browser.Document Msg
view model =
    let
        wrapMsg : List (Html Pages.Msg) -> List (Html Msg)
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
                , ul [ class "menu" ] (menuView model)
                ]
                :: (Pages.view model.page model.pages
                        |> wrapMsg
                   )
                ++ [ Toast.render viewToast model.toastTray toastConfig
                   , div [ class "footer" ]
                        [ div [ class "row" ]
                            [ a [ href "https://github.com/nyarly/wagthepig-harder" ] [ text "Contribute!" ]
                            , text " "
                            , a [ href "https://github.com/nyarly/wagthepig-harder/issues" ] [ s [] [ text "Complain!" ], text " Suggest!" ]
                            ]
                        , div [ class "row" ] [ img [ class "bgg-logo", src "http://localhost:3001/api/logos/color-rgb.svg" ] [] ]
                        ]
                   ]
            )
        ]
    }


menuView : Model -> List (Html Msg)
menuView model =
    if Auth.loggedIn model.creds then
        [ headerButton "Profile" "/profile"
        , headerButton "Events" "/events"
        , li [] [ button [ class "header", onClick SignOut ] [ text "Sign Out" ] ]
        ]

    else
        [ headerButton "Log In" "/login"
        ]


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
    in
    div attributes
        ((case toastInfo.content of
            MainToast Tester ->
                [ p [] [ text "This is a BRAND NEW test toast; this is only a test" ] ]

            MainToast NotAuthorized ->
                [ p [] [ text "You're no longer logged in" ]
                , button [ onClick (Relogin (stripToastInfo toastInfo)) ] [ text "Log In" ]
                ]

            MainToast CouldRetry ->
                [ p []
                    [ text "There was a transient error; maybe try that again" ]
                ]

            MainToast Unknown ->
                [ text "something weird went wrong - reach out to the devs!" ]

            PageToast subToast ->
                let
                    wrapHtml : List (Html Pages.Msg) -> List (Html Msg)
                    wrapHtml =
                        List.map (Html.map PageMsg)
                in
                Pages.viewToast (unwrapToast toastInfo subToast)
                    |> wrapHtml
         )
            ++ [ button [ class "toast-close", onClick (CloseToast (stripToastInfo toastInfo)) ] [ svgIcon "cross" ] ]
        )


stripToastInfo : Toast.Info c -> Toast.Info ()
stripToastInfo info =
    Toast.Info info.id info.phase info.interaction ()


headerButton : String -> String -> Html Msg
headerButton txt path =
    li [] [ button [ class "header", onClick (PathRequested path) ] [ text txt ] ]
