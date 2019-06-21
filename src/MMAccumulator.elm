module MMAccumulator exposing
    ( MMData
    , MMState
    , emptyMMState
    , getOrderedListItems
    , nextState
    , parse
    , parseReducer
    )

import MMParser exposing (MMBlock(..), MMInline(..), runBlocks)


type alias MMState =
    { itemIndex1 : Int
    , itemIndex2 : Int
    , itemIndex3 : Int
    , itemIndex4 : Int
    }


type alias MMData =
    ( List MMBlock, MMState )


emptyMMState =
    { itemIndex1 = 0
    , itemIndex2 = 0
    , itemIndex3 = 0
    , itemIndex4 = 0
    }


parse : MMState -> List String -> List MMData
parse mmState stringList =
    List.foldr parseReducer ( emptyMMState, [] ) (List.reverse stringList)
        |> Tuple.second
        |> List.reverse


parseReducer : String -> ( MMState, List MMData ) -> ( MMState, List MMData )
parseReducer str ( state, revAugmentedBlockLlist ) =
    let
        newBlockList =
            runBlocks (Debug.log "STR" str)

        newState =
            Debug.log "NEW STATE"
                (nextState (Debug.log "OLD STATE" state) newBlockList)
    in
    ( newState, ( newBlockList, newState ) :: revAugmentedBlockLlist )



-- nextState : MMState -> List MMBlock -> MMState


nextState state blockList =
    let
        oli =
            getOrderedListItems blockList

        -- |> List.map levelOrderedListItem
        -- |> List.filter (\c -> c > 0)
        n =
            Debug.log "N" <|
                List.length oli
    in
    { state | itemIndex1 = state.itemIndex1 + n, itemIndex2 = state.itemIndex2 + 1 }



-- state


{-|

> getOrderedListItems <| runBlocks "abc\\n\\n1. foo\\n\\ndef\\n\\n"
> [OrderedListItemBlock 1 (MMInlineList [OrdinaryText "foo"])]

-}
getOrderedListItems : List MMBlock -> List MMBlock
getOrderedListItems blockList =
    List.filter (\b -> levelOrderedListItem b > 0) blockList


levelOrderedListItem : MMBlock -> Int
levelOrderedListItem block =
    case block of
        OrderedListItemBlock k _ ->
            k

        _ ->
            0