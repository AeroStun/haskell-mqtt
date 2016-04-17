{-# LANGUAGE OverloadedStrings #-}
module Main where

import Control.Exception ( try, SomeException )

import qualified Data.Text as T
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as BS
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Attoparsec.ByteString as A
import qualified Data.Attoparsec.ByteString.Char8 as A

import Network.MQTT.Message
import Network.MQTT.Message.Utf8String
import Network.MQTT.Message.RemainingLength

import Prelude hiding (head)

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck as QC

main :: IO ()
main  = defaultMain $ testGroup "Network" [ testGroup "MQTT" [tgMessage]]

tgMessage :: TestTree
tgMessage = testGroup "Message"
  [ tgMessageRemainingLength
  , tgMessageUtf8String
  ]

tgMessageUtf8String :: TestTree
tgMessageUtf8String =
  testGroup "Utf8String"
  [ testCase "empty string" $ assertEqual ""
      ( Right "" )
      ( A.parseOnly pUtf8String $ BS.pack [0,0] )

  , testCase "string \"abc\"" $ assertEqual ""
      ( Right "abc" )
      ( A.parseOnly pUtf8String $ BS.pack [0,3,97,98,99] )

  , testCase "string of size 0x345" $ assertEqual ""
      ( Right $ T.replicate 0x345 "a" )
      ( A.parseOnly pUtf8String $ BS.pack $ [0x03,0x45] ++ replicate 0x0345 97 )

  , testCase "U+D800 [MQTT-1.5.3-1]" $ assertEqual ""
      ( Left "Failed reading: pUtf8String: violation of [MQTT-1.5.3]")
      ( A.parseOnly pUtf8String $ BS.pack [0,2,0xd8,0x01] )

  , testCase "U+DFFF [MQTT-1.5.3-1]" $ assertEqual ""
      ( Left "Failed reading: pUtf8String: violation of [MQTT-1.5.3]" )
      ( A.parseOnly pUtf8String $ BS.pack [0,2,0xdf,0xff] )

  , testCase "U+0000 [MQTT-1.5.3-2]" $ assertEqual ""
      ( Left "Failed reading: pUtf8String: violation of [MQTT-1.5.3-2]" )
      ( A.parseOnly pUtf8String $ BS.pack [0,1,0] )

  , testCase "U+FEFF [MQTT-1.5.3-3]" $ assertEqual ""
      ( Right "\65279" )
      ( A.parseOnly pUtf8String $ BS.pack [0x00,0x03,0xef,0xbb,0xbf] )

  , testCase "sUtf8String $ T.replicate 65536 \"a\"" $ do
     e <- try $ return $! BS.toLazyByteString $ sUtf8String $ T.replicate 65536 "a"
     case e :: Either SomeException LBS.ByteString of
       Left _  -> return ()
       Right _ -> assertFailure "Expected exception, instead got result."

  , testCase "pUtf8String . sUtf8String == id" $
      let txt = T.replicate 999 "abc"
      in assertEqual ""
      ( Right txt )
      ( A.parseOnly pUtf8String (LBS.toStrict $ BS.toLazyByteString (sUtf8String txt)))
  ]

tgMessageRemainingLength :: TestTree
tgMessageRemainingLength =
  testGroup "pRemainingLength, sRemainingLength"
  [ testCase "p [193,2] == 321" $ assertEqual ""
      ( Right 321 )
      ( A.parseOnly pRemainingLength $ BS.pack [193,2] )

  , testCase "p [0x00] == 0" $ assertEqual ""
      ( Right 0 )
      ( A.parseOnly pRemainingLength (BS.pack [0x00]) )

  , testCase "p [0x7f] == 127" $ assertEqual ""
      ( Right 127 )
      ( A.parseOnly pRemainingLength (BS.pack [0x7f]) )

  , testCase "p [0x80, 0x01] == 128" $ assertEqual ""
      ( Right 128 )
      ( A.parseOnly pRemainingLength (BS.pack [0x80, 0x01]) )

  , testCase "p [0xff, 0x7f] == 16383" $ assertEqual ""
      ( Right 16383 )
      ( A.parseOnly pRemainingLength (BS.pack [0xff, 0x7f]) )

  , testCase "p [0x80, 0x80, 0x01] == 16384" $ assertEqual ""
      ( Right 16384 )
      ( A.parseOnly pRemainingLength (BS.pack [0x80, 0x80, 0x01]) )

  , testCase "p [0xff, 0xff, 0x7f] == 2097151" $ assertEqual ""
      ( Right 2097151 )
      ( A.parseOnly pRemainingLength (BS.pack [0xff, 0xff, 0x7f]) )

  , testCase "p [0x80, 0x80, 0x80, 0x01] == 2097152" $ assertEqual ""
      ( Right 2097152 )
      ( A.parseOnly pRemainingLength (BS.pack [0x80, 0x80, 0x80, 0x01]) )

  , testCase "p [0xff, 0xff, 0xff, 0x7f] == 268435455" $ assertEqual ""
      ( Right 268435455 )
      ( A.parseOnly pRemainingLength (BS.pack [0xff, 0xff, 0xff, 0x7f]) )

  , testCase "p [0xff, 0xff, 0xff, 0xff] == invalid" $ assertEqual ""
      ( Left "Failed reading: pRemainingLength: invalid input" )
      ( A.parseOnly pRemainingLength (BS.pack [0xff, 0xff, 0xff, 0xff]) )

  , QC.testProperty "pRemainingLength . sRemainingLength == id" $
      \i -> let i' = i `mod` 268435455
            in  Right i' == A.parseOnly pRemainingLength (LBS.toStrict $ BS.toLazyByteString (sRemainingLength i'))
  ]