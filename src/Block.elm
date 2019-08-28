module Block exposing
    ( Block(..), parse, runFSM
    , BlockContent(..), MMBlock(..), parseToBlockTree, parseToMMBlockTree, stringOfBlockContent, stringOfBlockTree, stringOfMMBlockTree, updateRegister
    )

{-| A markdown document is parsed into a tree
of Blocks using

    parseToTree : String -> Tree Block

This function applies

    parse : String -> List Block

and then the partially applied function

    HTree.fromList rootBlock blockLevel :
       List Block -> Tree Block

This last step is possible because the elements of `List Block`
are annotated by their level.
The `parse` function operated by running a finite-state machine.
Thie machine has type

    type FSM
        = FSM State (List Block)

where the three possible states are defined by

    type State
        = Start
        | InBlock Block
        | Error

If the FSM consumes all its input and no error
id encountered, then the `(List Block)` component of the FSM contains
the result of parsing the input string into blocks.

@docs Block, parseToTree, parse, runFSM

-}

import BlockType exposing (BalancedType(..), BlockType(..), MarkdownType(..))
import HTree
import MMInline exposing (MMInline(..))
import Tree exposing (Tree)



-- BLOCK --


{-| A Block is defined as follows:

    type Block
        = Block BlockType Level Content

    type alias Level =
        Int

    type alias Content =
        String

-}
type Block
    = Block BlockType Level Content


type MMBlock
    = MMBlock BlockType Level BlockContent


type BlockContent
    = M MMInline
    | T String


type alias Level =
    Int


type alias Content =
    String



-- FSM --


type FSM
    = FSM State (List Block) Register


type alias Register =
    { itemIndex1 : Int
    , itemIndex2 : Int
    , itemIndex3 : Int
    , itemIndex4 : Int
    }


emptyRegister : Register
emptyRegister =
    { itemIndex1 = 0
    , itemIndex2 = 0
    , itemIndex3 = 0
    , itemIndex4 = 0
    }


type State
    = Start
    | InBlock Block
    | Error


{-|

    parseToTree  "- One\nsome stuff\n- Two\nMore stuff"
    -->    Tree (Block (MarkdownBlock Plain) 0 "*") [
    -->      Tree (Block (MarkdownBlock UListItem) 1 ("- One\nsome stuff\n")) []
    -->      ,Tree (Block (MarkdownBlock UListItem) 1 ("- Two\nMore stuff\n")) []
    -->    ]

-}
parseToBlockTree : String -> Tree Block
parseToBlockTree str =
    str
        |> parse
        |> List.map (changeLevel 1)
        |> HTree.fromList rootBlock blockLevel


changeLevel : Int -> Block -> Block
changeLevel k (Block bt_ level_ content_) =
    Block bt_ (level_ + k) content_


parseToMMBlockTree : String -> Tree MMBlock
parseToMMBlockTree str =
    let
        mapper : Block -> MMBlock
        mapper (Block bt level_ content_) =
            case bt of
                MarkdownBlock mt ->
                    MMBlock (MarkdownBlock mt) level_ (M (MMInline.parse content_))

                BalancedBlock DisplayCode ->
                    MMBlock (BalancedBlock DisplayCode) level_ (T content_)

                BalancedBlock Verbatim ->
                    MMBlock (BalancedBlock Verbatim) level_ (T content_)

                BalancedBlock DisplayMath ->
                    MMBlock (BalancedBlock DisplayMath) level_ (T content_)
    in
    str
        |> parseToBlockTree
        |> Tree.map mapper


{-|

    parse "- One\nsome stuff\n- Two\nMore stuff"
    --> [ Block (MarkdownBlock UListItem)
    -->    1 ("- One\nsome stuff\n")
    -->  ,Block (MarkdownBlock UListItem)
    -->    1 ("- Two\nMore stuff\n")
    --> ]

-}
parse : String -> List Block
parse str =
    runFSM str |> flush


{-|

    runFSM  "- One\nsome stuff\n- Two\nMore stuff"
    --> FSM (InBlock (Block (MarkdownBlock UListItem)
    -->        1 ("- Two\nMore stuff\n")))
    -->     [Block (MarkdownBlock UListItem)
    -->        1 ("- One\nsome stuff\n")]

-}
runFSM : String -> FSM
runFSM str =
    let
        folder : String -> FSM -> FSM
        folder =
            \line fsm -> nextState line fsm
    in
    List.foldl folder initialFSM (splitIntoLines str)


blockLevel : Block -> Int
blockLevel (Block _ k _) =
    k


type_ : Block -> BlockType
type_ (Block bt _ _) =
    bt


typeOfState : State -> Maybe BlockType
typeOfState s =
    case s of
        Start ->
            Nothing

        InBlock b ->
            Just (type_ b)

        Error ->
            Nothing


rootBlock =
    Block (MarkdownBlock Root) 0 "DOCUMENT"


flush : FSM -> List Block
flush fsm =
    case stateOfFSM fsm of
        Start ->
            List.reverse (blockListOfFSM fsm)

        Error ->
            List.reverse (blockListOfFSM fsm)

        InBlock b ->
            List.reverse (b :: blockListOfFSM fsm)


stateOfFSM : FSM -> State
stateOfFSM (FSM state_ _ _) =
    state_


blockListOfFSM : FSM -> List Block
blockListOfFSM (FSM _ blockList_ _) =
    blockList_


splitIntoLines : String -> List String
splitIntoLines str =
    str
        |> String.lines
        |> List.map (\l -> l ++ "\n")


initialFSM : FSM
initialFSM =
    FSM Start [] emptyRegister


nextState : String -> FSM -> FSM
nextState str fsm =
    case stateOfFSM fsm of
        Start ->
            nextStateS str fsm

        InBlock _ ->
            nextStateIB str fsm

        Error ->
            fsm


nextStateS : String -> FSM -> FSM
nextStateS line (FSM state blockList register) =
    case BlockType.get line of
        ( _, Nothing ) ->
            FSM Error blockList register

        -- add line
        ( level, Just blockType ) ->
            let
                ( newBlockType, newRegister ) =
                    updateRegister blockType level register

                line_ =
                    removePrefix blockType line
            in
            FSM (InBlock (Block newBlockType level line_)) blockList newRegister


removePrefix : BlockType -> String -> String
removePrefix blockType line_ =
    let
        p =
            BlockType.prefixOfBlockType blockType line_
    in
    String.replace p "" line_


nextStateIB : String -> FSM -> FSM
nextStateIB line ((FSM state_ blocks_ register) as fsm) =
    case BlockType.get line of
        ( _, Nothing ) ->
            FSM Error (blockListOfFSM fsm) register

        ( level, Just blockType ) ->
            -- process balanced block
            if BlockType.isBalanced blockType then
                processBalancedBlock blockType line fsm
                -- add markDown block d

            else if BlockType.isMarkDown blockType then
                processMarkDownBlock blockType line fsm

            else
                fsm


processMarkDownBlock : BlockType -> String -> FSM -> FSM
processMarkDownBlock blockTypeOfLine line ((FSM state blocks_ register) as fsm) =
    let
        _ =
            Debug.log "STATE (PMDB)" state
    in
    case state of
        -- add current block to block list and
        -- start new block with the current line and lineType
        InBlock ((Block typeOfCurrentBlock levelOfCurrentBlock _) as currentBlock) ->
            let
                adjustedCurrentBlock =
                    adjustLevel currentBlock
            in
            if BlockType.isBalanced typeOfCurrentBlock then
                -- add line to current balanced block
                addLineToFSM (Debug.log "MD1 (ADD BALANCED)" line) fsm

            else if blockTypeOfLine == MarkdownBlock Blank then
                -- start new block
                FSM Start (Debug.log "MD1 (START)" adjustedCurrentBlock :: blocks_) register

            else if blockTypeOfLine == MarkdownBlock Plain then
                -- continue, add content to current block
                addLineToFSM (Debug.log "MD1 (ADD)" line) fsm

            else
                -- start new block
                let
                    ( newBlockType, newRegister ) =
                        updateRegister typeOfCurrentBlock levelOfCurrentBlock register

                    line_ =
                        removePrefix typeOfCurrentBlock line
                in
                FSM (InBlock (Block newBlockType (BlockType.level (Debug.log "MD1 CR" line)) line_)) (adjustedCurrentBlock :: blocks_) newRegister

        _ ->
            fsm



-- addNewBlock : BlockType -> String -> FSM -> FSM
-- addNewBlock blockType line ((FSM state blocks register) as fsm) =
--     let
--         ( newBlockType, newRegister ) =
--             updateRegister blockType lev_ register
--
--         line_ =
--             removePrefix typeOfCurrentBlock line
--         level = BlockType.level (Debug.log "MD1 CR" line)
--         block =
--             Block blockType level line
--     in
--     FSM Start (Debug.log "MD1 (START)" block :: blocks) register


adjustLevel : Block -> Block
adjustLevel ((Block blockType level content) as block) =
    if blockType == MarkdownBlock Plain then
        let
            newLevel =
                Debug.log "NEW LEVEL" <|
                    BlockType.level content
        in
        Block blockType newLevel content

    else
        block


processBalancedBlock : BlockType -> String -> FSM -> FSM
processBalancedBlock lineType line ((FSM state_ blocks_ register) as fsm) =
    -- the currently processed block should be closed and a new one opened
    if Just lineType == typeOfState (stateOfFSM fsm) then
        case stateOfFSM fsm of
            InBlock block_ ->
                let
                    line_ =
                        removePrefix lineType line
                in
                FSM Start (addLineToBlock (Debug.log "CLOSE" line_) block_ :: blocks_) register

            _ ->
                fsm
        -- open balanced block

    else
        case stateOfFSM fsm of
            InBlock block_ ->
                FSM (InBlock (Block lineType (BlockType.level (Debug.log "OPEN" line)) line)) (block_ :: blocks_) register

            _ ->
                fsm


updateRegister : BlockType -> Int -> Register -> ( BlockType, Register )
updateRegister blockType level_ register =
    if BlockType.isOListItem blockType then
        let
            ( index, newRegister ) =
                incrementRegister level_ register

            newBlockType =
                MarkdownBlock (OListItem index)
        in
        ( newBlockType, newRegister )

    else
        ( blockType, register )


incrementRegister : Int -> Register -> ( Int, Register )
incrementRegister level register =
    case level + 1 of
        1 ->
            ( register.itemIndex1 + 1
            , { register
                | itemIndex1 = register.itemIndex1 + 1
                , itemIndex2 = 0
                , itemIndex3 = 0
                , itemIndex4 = 0
              }
            )

        2 ->
            ( register.itemIndex2 + 1
            , { register
                | itemIndex2 = register.itemIndex2 + 1
                , itemIndex3 = 0
                , itemIndex4 = 0
              }
            )

        3 ->
            ( register.itemIndex3 + 1
            , { register
                | itemIndex3 = register.itemIndex3 + 1
                , itemIndex4 = 0
              }
            )

        4 ->
            ( register.itemIndex4 + 1, { register | itemIndex4 = register.itemIndex4 + 1 } )

        _ ->
            ( 0, register )


addLineToFSM : String -> FSM -> FSM
addLineToFSM str (FSM state_ blocks_ register) =
    case state_ of
        Start ->
            FSM state_ blocks_ register

        Error ->
            FSM state_ blocks_ register

        InBlock _ ->
            FSM (addLineToState str state_) blocks_ register


addLineToState : String -> State -> State
addLineToState str state_ =
    case state_ of
        Start ->
            Start

        Error ->
            Error

        InBlock block_ ->
            InBlock (addLineToBlock str block_)


addLineToBlock : String -> Block -> Block
addLineToBlock str (Block blockType_ level_ content_) =
    Block blockType_ level_ (content_ ++ str)



-- STRING --


stringOfBlockTree : Tree Block -> String
stringOfBlockTree tree =
    tree
        |> Tree.flatten
        |> List.map stringOfBlock
        |> String.join "\n"


stringOfBlock : Block -> String
stringOfBlock (Block bt lev_ content_) =
    String.repeat (2 * lev_) " "
        ++ BlockType.stringOfBlockType bt
        ++ " ("
        ++ String.fromInt lev_
        ++ ") "
        ++ "\n"
        ++ indent lev_ content_


indent : Int -> String -> String
indent k str =
    str
        |> String.split "\n"
        |> List.map (\s -> String.repeat (2 * k) " " ++ s)
        |> String.join "\n"



-- STRING --


stringOfMMBlockTree : Tree MMBlock -> String
stringOfMMBlockTree tree =
    tree
        |> Tree.flatten
        |> List.map stringOfMMBlock
        |> String.join "\n"


stringOfMMBlock : MMBlock -> String
stringOfMMBlock (MMBlock bt lev_ content_) =
    String.repeat (2 * lev_) " "
        ++ BlockType.stringOfBlockType bt
        ++ " ("
        ++ String.fromInt lev_
        ++ ") "
        ++ indent lev_ (stringOfBlockContent content_)


stringOfBlockContent : BlockContent -> String
stringOfBlockContent blockContent =
    case blockContent of
        M mmInline ->
            stringOfMMInline mmInline

        T str ->
            str


stringOfMMInline : MMInline -> String
stringOfMMInline mmInline =
    MMInline.string mmInline
