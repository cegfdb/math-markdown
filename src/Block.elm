module Block exposing
    ( Block(..), MMBlock(..), BlockContent(..), parseToBlockTree, parseToMMBlockTree, parse, runFSM
    , stringOfBlockTree, stringOfMMBlockTree, stringOfBlockContent)

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

import HTree
import LineType exposing (BalancedType(..), BlockType(..), MarkdownType(..))
import Tree exposing (Tree)
import MMInline exposing(MMInline(..))

-- BLOCK --

{-| A Block is defined as follows:

    type Block
        = Block BlockType Level Content

    type alias Level =
        Int

    type alias Content =
        String

-}
type Block = Block BlockType Level Content

type MMBlock = MMBlock BlockType Level BlockContent

type BlockContent = M MMInline | T String

type alias Level =
    Int

type alias Content =
    String

-- FSM --



type FSM
    = FSM State (List Block)


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
       normalize bt str_ =
           case bt of
               BalancedBlock bt_ -> String.replace (LineType.prefixOfBalancedType bt_) "" str_
               MarkdownBlock mt -> String.replace (LineType.prefixOfMarkdownType mt) "" str_
       mapper : Block -> MMBlock
       mapper (Block bt level_ content_) =
           case bt of
               MarkdownBlock mt -> (MMBlock (MarkdownBlock mt) level_ (M  (MMInline.parse (normalize bt content_))))
               BalancedBlock DisplayCode -> (MMBlock (BalancedBlock DisplayCode)) level_ (T (normalize bt content_))
               BalancedBlock Verbatim -> (MMBlock (BalancedBlock Verbatim)) level_ (T (normalize bt content_))
               BalancedBlock DisplayMath -> (MMBlock (BalancedBlock DisplayMath)) level_ (T (normalize bt content_))
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
    Block (MarkdownBlock Plain) 0 "DOCUMENT"


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
stateOfFSM (FSM state_ _) =
    state_


blockListOfFSM : FSM -> List Block
blockListOfFSM (FSM _ blockList_) =
    blockList_


splitIntoLines : String -> List String
splitIntoLines str =
    str |> String.lines
        |> List.map (\l -> l ++ "\n")



initialFSM : FSM
initialFSM =
    FSM Start []


nextState : String -> FSM -> FSM
nextState str fsm =
    case stateOfFSM fsm of
        Start ->
            nextStateS str fsm

        InBlock _ ->
            nextStateB str fsm

        Error ->
            fsm


nextStateS : String -> FSM -> FSM
nextStateS line (FSM state blockList) =
    case LineType.get line of
        ( _, Nothing ) ->
            FSM Error blockList

        ( level, Just blockType ) ->
            FSM (InBlock (Block blockType level (Debug.log "START" line))) blockList


nextStateB1 : String -> FSM -> FSM
nextStateB1 line fsm =
    fsm


nextStateB : String -> FSM -> FSM
nextStateB line ((FSM state_ blocks_) as fsm) =
    case LineType.get line of
        ( _, Nothing ) ->
            FSM Error (blockListOfFSM fsm)

        ( level, Just lineType ) ->

            -- process balanced block
            if LineType.isBalanced lineType then
              processBalancedBlock lineType line fsm

            -- add markDown block d
            else if LineType.isMarkDown lineType then
              processMarkDownBlock lineType line fsm

            else
                fsm

processMarkDownBlock : BlockType -> String -> FSM -> FSM
processMarkDownBlock lineType line fsm =
   case stateOfFSM fsm of
        -- add current block to block list and
        -- start new block with the current line and lineType

        InBlock ((Block bt lev_ content_) as block_) ->
           -- start new block
           if lineType == MarkdownBlock Blank then
             FSM Start ((Debug.log "MD1 (START)" block_) :: blockListOfFSM fsm)

           -- continue, add content to current block
           else if lineType == MarkdownBlock Plain then
              addLineToFSM (Debug.log "MD1 (ADD)" line) fsm
           -- start new block
           else
              FSM (InBlock (Block lineType (LineType.level (Debug.log "MD1 START(2)" line)) line)) (block_ :: blockListOfFSM fsm)


        _ ->
            fsm


processBalancedBlock : BlockType -> String -> FSM -> FSM
processBalancedBlock lineType line fsm =
    -- the currently processed block should be closed and a new one opened
    if Just lineType == typeOfState (stateOfFSM fsm) then
        case stateOfFSM fsm of
            InBlock block_ ->
                FSM Start (addLineToBlock (Debug.log "CLOSE" line) block_ :: blockListOfFSM fsm)

            _ ->
                fsm
    -- open balanced block
    else
      case stateOfFSM fsm of
        InBlock block_ ->
            FSM (InBlock (Block lineType (LineType.level (Debug.log "OPEN" line)) line)) (block_ :: blockListOfFSM fsm)

        _ ->
            fsm


addLineToFSM : String -> FSM -> FSM
addLineToFSM str (FSM state_ blocks_) =
    case state_ of
        Start ->
            FSM state_ blocks_

        Error ->
            FSM state_ blocks_

        InBlock _ ->
            FSM (addLineToState str state_) blocks_


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
    ++
    LineType.stringOfBlockType bt
    ++
    " (" ++ String.fromInt lev_ ++ ") "
    ++ "\n" ++ indent lev_ content_

indent : Int -> String -> String
indent k str =
    str
      |> String.split "\n"
      |> List.map (\s -> (String.repeat (2 * k) " ") ++ s)
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
    ++
    LineType.stringOfBlockType bt
    ++
    " (" ++ String.fromInt lev_ ++ ") "
    ++ indent lev_ (stringOfBlockContent content_)

stringOfBlockContent : BlockContent -> String
stringOfBlockContent blockContent =
      case blockContent of
          M mmInline -> stringOfMMInline mmInline
          T str -> str



stringOfMMInline : MMInline -> String
stringOfMMInline mmInline =
     MMInline.string mmInline