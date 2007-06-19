-----------------------------------------------------------------------------
-- |
-- Module      :  XMobar
-- Copyright   :  (c) Andrea Rossato
-- License     :  BSD-style (see xmonad/LICENSE)
-- 
-- Maintainer  :  Andrea Rossato <andrea.rossato@unibz.it>
-- Stability   :  unstable
-- Portability :  unportable
--
-- A status bar for the Xmonad Window Manager 
--
-----------------------------------------------------------------------------

module Main where

import Graphics.X11.Xlib
import Graphics.X11.Xlib.Misc
import Graphics.X11.Xlib.Extras

import Text.ParserCombinators.Parsec

import Control.Concurrent
import Control.Monad
import Data.Bits
import System

data Config = 
    Config { fonts :: String
           , bgColor :: String
           , fgColor :: String
           , xPos :: Int
           , yPos :: Int
           , width :: Int
           , hight :: Int
           } deriving (Eq, Show, Read, Ord)

defaultConfig :: Config
defaultConfig =
    Config { fonts = "-misc-fixed-*-*-*-*-*-*-*-*-*-*-*-*" 
           , bgColor = "#000000"
           , fgColor = "#ffffff"
           , xPos = 0
           , yPos = 0
           , width = 1024
           , hight = 15
           }

main :: IO ()
main = 
    do args <- getArgs
       config <-
           if length args /= 1
              then do putStrLn ("No configuration file specified. Using default settings.")
                      return defaultConfig
              else readConfig (args!!0)
       eventLoop config

eventLoop :: Config -> IO ()
eventLoop c =
    do i <- getLine
       ps <- stringParse c i
       w <- createWin c
       runWin c w ps

createWin :: Config -> IO (Display, Window)
createWin config =
  do dpy   <- openDisplay ""
     let dflt = defaultScreen dpy
     rootw  <- rootWindow dpy dflt
     win <- mkUnmanagedWindow dpy (defaultScreenOfDisplay dpy) rootw 
            (fromIntegral $ xPos config) 
            (fromIntegral $ yPos config) 
            (fromIntegral $ width config) 
            (fromIntegral $ hight config) 0
     mapWindow dpy win
     return (dpy,win)

runWin :: Config -> (Display, Window) -> [(String, String)] -> IO ()
runWin config (dpy, win) str = do
  -- get default colors
  bgcolor  <- initColor dpy $ bgColor config
  fgcolor  <- initColor dpy $ fgColor config

  -- window background 
  gc <- createGC dpy win
  setForeground dpy gc bgcolor
  fillRectangle dpy win gc 0 0 
                    (fromIntegral $ width config) 
                    (fromIntegral $ hight config)

  -- let's get the fonts
  fontst <- loadQueryFont dpy (fonts config)
  setFont dpy gc (fontFromFontStruct fontst)
  
  -- print what you need to print
  let strWithLenth = map (\(s,c) -> (s,c,textWidth fontst s)) str
  printStrings dpy win gc fontst 1 strWithLenth 

  -- refreesh, fre, resync... do what you gotta do
  freeGC dpy gc
  sync dpy True
  -- back again: we are never ending
  eventLoop config


{- $print
An easy way to print the stuff we need to print
-}

printStrings _ _ _ _ _ [] = return ()
printStrings dpy win gc fontst offset (x@(s,c,l):xs) =
    do let (_,asc,desc,_) = textExtents fontst s
       color  <- initColor dpy c
       setForeground dpy gc color
       drawString dpy win gc offset asc s
       printStrings dpy win gc fontst (offset + l) xs

{- $parser
This is suppose do be a parser. Don't trust him.
-}

stringParse :: Config -> String -> IO [(String, String)]
stringParse config s = 
    case (parse (stringParser config) "" s) of
      Left err -> return [("Sorry, if I were a decent parser you now would be starring at something meaningful...",(fgColor config))]
      Right x  -> return x

stringParser :: Config -> Parser [(String, String)]
stringParser c = manyTill (choice [colorsAndText c,defaultColors c]) eof

defaultColors :: Config -> Parser (String, String)
defaultColors config = 
    do { s <- many $ noneOf "^"
       ; notFollowedBy (char '#')
       ; return (s,(fgColor config))
       }
    <|> colorsAndText config

colorsAndText :: Config -> Parser (String, String) 
colorsAndText config = 
    do { string "^#"
       ; n <- count 6 hexDigit
       ; s <- many $ noneOf "^"
       ; notFollowedBy (char '#') 
       ; return (s,"#"++n)
       }
    <|> defaultColors config


{- $unmanwin

This is a way to create unmamaged window. It was a mistery in haskell. 
Till I've found out...;-)

-}

mkUnmanagedWindow :: Display
                  -> Screen
                  -> Window
                  -> Position
                  -> Position
                  -> Dimension
                  -> Dimension
                  -> Pixel
                  -> IO Window
mkUnmanagedWindow dpy scr rw x y w h bgcolor = do
  let visual = defaultVisualOfScreen scr
      attrmask = cWOverrideRedirect
  window <- allocaSetWindowAttributes $ 
            \attributes -> do
              set_override_redirect attributes True
              createWindow dpy rw x y w h 0 (defaultDepthOfScreen scr) 
                           inputOutput visual attrmask attributes                                
  return window

{- $utility

Utilitis, aka stollen without givin' credit stuff.

-}

readConfig :: FilePath -> IO Config
readConfig f = 
    do s <- readFile f
       case reads s of
         [(config, str)] -> return config
         [] -> error ("corrupt config file: " ++ f)

-- | Get the Pixel value for a named color
initColor :: Display -> String -> IO Pixel
initColor dpy c = (color_pixel . fst) `liftM` allocNamedColor dpy colormap c
    where colormap = defaultColormap dpy (defaultScreen dpy)

