module EventGames exposing (view)


view : Model -> List (Html Msg)
view model =
    [ h1 [] [ text "Events" ]
    , createEventButton model.resource
    , table []
        [ thead []
            [ th [] [ text "Name" ]
            , th [] [ text "Date" ]
            , th [] [ text "Where" ]
            , th [ colspan 3 ] []
            ]
        , Keyed.node "tbody" [] (List.foldr addRow [] model.resource.events)
        ]
    ]


addRow : Event -> List ( String, Html Msg ) -> List ( String, Html Msg )
addRow event list =
    ( event.id
    , tr []
        [ td [] [ text event.name ]
        , td [] [ text (String.fromInt (Time.posixToMillis event.time)) ]
        , td [] [ text event.location ]
        , td [] [ text "Show" ]
        , td [] [ eventEditButton event ]
        ]
    )
        :: list
