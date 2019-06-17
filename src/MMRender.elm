module MMRender exposing (render, renderBlock, renderClosedBlock)

import Html exposing (..)
import Html.Attributes exposing (style)
import MMParser exposing (MMBlock(..), MMInline(..))


{-|

> runBlocks "~~Elimininate this~~, _please_\\n\\n" |> render
> <internals> : Html.Html msg

-}
render : List (Html.Attribute msg) -> List MMBlock -> Html msg
render attrList blockList =
    List.map renderBlock blockList
        |> (\stuff -> div attrList stuff)


{-|

> runBlocks "~~Elimininate this~~, _please_\\n\\n" |> List.map renderBlock
> [<internals>] : List (Html.Html msg)

-}
renderBlock : MMBlock -> Html msg
renderBlock block_ =
    case block_ of
        MMList list ->
            div [] (List.map renderBlock list)

        Block block__ ->
            div [] [ text "Block" ]

        RawBlock str ->
            div [] [ text str ]

        HeadingBlock level str ->
            case level of
                1 ->
                    h1 [ style "font-size" "24pt" ] [ text str ]

                2 ->
                    h1 [ style "font-size" "18pt" ] [ text str ]

                _ ->
                    h5 [] [ text str ]

        MathDisplayBlock str ->
            div [] [ text <| "$$" ++ str ++ "$$" ]

        CodeBlock str ->
            pre [] [ text str ]

        ListItemBlock k str ->
            let
                margin =
                    Debug.log "OFFSET" <|
                        String.fromInt (12 * k)
                            ++ "px"
            in
            li [ style "margin-left" margin ] [ text str ]

        ClosedBlock mmInline ->
            renderClosedBlock mmInline


renderClosedBlock : MMInline -> Html msg
renderClosedBlock mmInline =
    case mmInline of
        OrdinaryText str ->
            span [] [ text str ]

        ItalicText str ->
            em [] [ text str ]

        BoldText str ->
            strong [] [ text str ]

        StrikeThroughText str ->
            span [ style "text-decoration" "line-through" ] [ text str ]

        Code str ->
            span [ style "font" "Coureir, Monaco, monospace" ] [ text str ]

        InlineMath str ->
            span [] [ text <| "$" ++ str ++ "$" ]

        MMInlineList list ->
            div [ style "margin-bottom" "12px" ] (List.map renderClosedBlock list)

        Error _ ->
            div [] [ text "Error" ]



-- [ClosedBlock (MMInlineList [ItalicText ("foo "),OrdinaryText ("ha ha ha"),OrdinaryText ("ho ho ho"),InlineMath ("a^6 + 2")]),MathDisplayBlock ("a^2 = 3")]
--     : List MMBlock
