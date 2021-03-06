module Data.Units
  ( Prefix
  , DerivedUnit()
  , withPrefix
  , simplify
  , makeStandard
  , makeNonStandard
  -- Conversions
  , toStandardUnit
  , prefixName
  , toStringWithPrefix
  , toString
  -- Mathematical operations on units
  , power
  , (.^)
  , divideUnits
  , (./)
  -- One
  , unity
  -- Prefixes
  , atto
  , femto
  , pico
  , nano
  , micro
  , centi
  , deci
  , hecto
  , milli
  , kilo
  , mega
  , giga
  , tera
  , peta
  , exa
  ) where

import Prelude

import Data.Foldable (intercalate, sum, foldMap, product)
import Data.List (List(Nil), singleton, (:), span, sortBy, filter, findIndex,
                  modifyAt)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Monoid (class Monoid)
import Data.NonEmpty (NonEmpty, (:|), head)
import Data.Tuple (Tuple(..), fst, snd)

import Math (pow)

-- | A factor which is used to convert between two units. For the conversion
-- | from `minute` to `second`, the conversion factor would be `60.0`.
type ConversionFactor = Number

-- | A base unit can either be a standardized unit or some non-standard unit.
-- | In the latter case, a conversion to a standard unit must be provided.
data UnitType
  = Standard
  | NonStandard
      { standardUnit :: DerivedUnit
      , factor       :: ConversionFactor
      }

instance eqUnitType :: Eq UnitType where
  eq Standard Standard = true
  eq (NonStandard rec1) (NonStandard rec2) = rec1.standardUnit == rec2.standardUnit
                                          &&       rec1.factor == rec2.factor
  eq _ _ = false

-- | A (single) physical unit, for example *meter* or *second*.
newtype BaseUnit = BaseUnit
  { long     :: String
  , short    :: String
  , unitType :: UnitType
  }

-- | The short name of a base unit (*meter* -> *m*, *second* -> *s*, ..).
shortName :: BaseUnit → String
shortName (BaseUnit u) = u.short

-- | The long name of a base unit (*meter*, *second*, ..).
longName :: BaseUnit → String
longName (BaseUnit u) = u.long

instance eqBaseUnit :: Eq BaseUnit where
  eq (BaseUnit u1) (BaseUnit u2) =     u1.long == u2.long
                                &&    u1.short == u2.short
                                && u1.unitType == u2.unitType

instance showBaseUnit :: Show BaseUnit where
  show = longName

-- | Test whether or not a given `BaseUnit` is a standard unit.
isStandardUnit :: BaseUnit → Boolean
isStandardUnit (BaseUnit u) =
  case u.unitType of
    Standard → true
    _        → false

-- | Convert a base unit to a standard unit.
baseToStandard :: BaseUnit → DerivedUnit
baseToStandard bu@(BaseUnit u) =
  case u.unitType of
      Standard → fromBaseUnit bu
      NonStandard { standardUnit, factor } → standardUnit

conversionFactor :: BaseUnit → ConversionFactor
conversionFactor (BaseUnit u) =
  case u.unitType of
      Standard → one
      NonStandard { standardUnit, factor } → factor


type Prefix = Number
type Exponent = Number

-- | Type alias for something like *m³*, *s⁻¹*, *km²* or similar A prefix.
-- | value of `p` represents an additional factor of `10^p`.
type BaseUnitWithExponent = { prefix   :: Prefix
                            , baseUnit :: BaseUnit
                            , exponent :: Exponent }

-- | A `DerivedUnit` is a product of `BaseUnits`, raised to arbitrary powers.
-- | The `Semigroup`/`Monoid` instance implements multiplication of units. A
-- | `DerivedUnit` also has a `Prefix` value, which represents a numerical
-- | prefix as a power of ten.
data DerivedUnit = DerivedUnit (List BaseUnitWithExponent)

-- | Expose the underlying list of base units.
runDerivedUnit :: DerivedUnit → List BaseUnitWithExponent
runDerivedUnit (DerivedUnit u) = u

-- | Add a given prefix value to a unit. `withPrefix 3.0 meter = kilo meter`.
withPrefix :: Prefix → DerivedUnit → DerivedUnit
withPrefix p (DerivedUnit Nil) =
  DerivedUnit $ singleton { prefix: p, baseUnit: unity', exponent: 1.0 }
withPrefix p (DerivedUnit us) = DerivedUnit $
  case findIndex (\u -> u.exponent == 1.0) us of
    Just ind →
      fromMaybe us (modifyAt ind (\u → u { prefix = u.prefix + p }) us)
    Nothing → { prefix: p, baseUnit: unity', exponent: 1.0 } : us

-- | Alternative implementation of `Data.List.groupBy` with a (more) useful
-- | return type.
groupBy :: ∀ a. (a → a → Boolean) → List a → List (NonEmpty List a)
groupBy _ Nil = Nil
groupBy eq (x : xs) = case span (eq x) xs of
  { init: ys, rest: zs } → (x :| ys) : groupBy eq zs

-- | Simplify the internal representation of a `DerivedUnit` by merging base
-- | units of the same type. For example, *m·s·m* will by simplified to *m²·s*.
simplify :: DerivedUnit → DerivedUnit
simplify (DerivedUnit list) = DerivedUnit (go list)
  where
    go = sortBy (comparing (_.baseUnit >>> shortName))
           >>> groupBy (\u1 u2 → u1.baseUnit == u2.baseUnit
                                && u1.prefix == u2.prefix)
           >>> map merge
           >>> filter (\x → not (x.exponent == 0.0))
    merge units = { prefix: (head units).prefix
                  , baseUnit: (head units).baseUnit
                  , exponent: sum $ _.exponent <$> units }

instance eqDerivedUnit :: Eq DerivedUnit where
  eq u1 u2 = (_.baseUnit <$> list1' == _.baseUnit <$> list2')
          && (_.exponent <$> list1' == _.exponent <$> list2')
          && globalPrefix list1 == globalPrefix list2
    where
      -- TODO: get rid of `unity'` and re-write the Eq instance
      list1' = filter (\u → longName u.baseUnit /= "unity") list1
      list2' = filter (\u → longName u.baseUnit /= "unity") list2
      list1 = runDerivedUnit (simplify u1)
      list2 = runDerivedUnit (simplify u2)

      globalPrefix :: List BaseUnitWithExponent → Prefix
      globalPrefix us = sum $ map (\{prefix, baseUnit, exponent} → prefix * exponent) us

instance showDerivedUnit :: Show DerivedUnit where
  show (DerivedUnit us) = listString us
    where
      listString Nil       = "unity"
      listString (u : Nil) = show' u
      listString us'       = "(" <> intercalate " <> " (show' <$> us') <> ")"

      addPrf  -18.0 str = "(atto "  <> str <> ")"
      addPrf  -15.0 str = "(femto " <> str <> ")"
      addPrf  -12.0 str = "(pico "  <> str <> ")"
      addPrf   -9.0 str = "(nano "  <> str <> ")"
      addPrf   -6.0 str = "(micro " <> str <> ")"
      addPrf   -3.0 str = "(milli " <> str <> ")"
      addPrf    0.0 str = str
      addPrf    3.0 str = "(kilo "  <> str <> ")"
      addPrf    6.0 str = "(mega "  <> str <> ")"
      addPrf    9.0 str = "(giga "  <> str <> ")"
      addPrf   12.0 str = "(tera "  <> str <> ")"
      addPrf   15.0 str = "(peta "  <> str <> ")"
      addPrf   18.0 str = "(exa "   <> str <> ")"
      addPrf prefix str = "(withPrefix (" <> show prefix <> ") (" <> str <> "))"

      show' { prefix, baseUnit, exponent: 1.0 } = addPrf prefix (show baseUnit)
      show' { prefix: 0.0, baseUnit, exponent }      =
        show baseUnit <> " .^ (" <> show exponent <> ")"
      show' { prefix, baseUnit, exponent }      =
        addPrf prefix (show baseUnit) <> " .^ (" <> show exponent <> ")"

instance semigroupDerivedUnit :: Semigroup DerivedUnit where
  append (DerivedUnit u1) (DerivedUnit u2) =
    simplify $ DerivedUnit (u1 <> u2)

instance monoidDerivedUnit :: Monoid DerivedUnit where
  mempty = unity

-- | Helper function to create a standard unit.
makeStandard :: String → String → DerivedUnit
makeStandard long short = fromBaseUnit $
  BaseUnit { short, long, unitType: Standard }

-- | Helper function to create a non-standard unit.
makeNonStandard :: String → String → ConversionFactor → DerivedUnit
                   → DerivedUnit
makeNonStandard long short factor standardUnit = fromBaseUnit $
  BaseUnit { short, long, unitType: NonStandard { standardUnit, factor } }

-- | Convert all contained units to standard units and return the global
-- | conversion factor.
toStandardUnit :: DerivedUnit → Tuple DerivedUnit ConversionFactor
toStandardUnit (DerivedUnit units) = Tuple units' conv
  where
    conv = product (snd <$> converted)
    units' = foldMap fst converted

    converted = convert <$> units

    convert :: BaseUnitWithExponent → Tuple DerivedUnit Number
    convert { prefix, baseUnit, exponent } =
      Tuple ((baseToStandard baseUnit) .^ exponent)
            ((10.0 `pow` prefix * conversionFactor baseUnit) `pow` exponent)

-- | Get the name of a SI-prefix.
prefixName :: Prefix → Maybe String
prefixName -18.0 = Just "a"
prefixName -15.0 = Just "f"
prefixName -12.0 = Just "p"
prefixName  -9.0 = Just "n"
prefixName  -6.0 = Just "µ"
prefixName  -3.0 = Just "m"
prefixName  -2.0 = Just "c"
prefixName  -1.0 = Just "d"
prefixName   0.0 = Just ""
prefixName   2.0 = Just "h"
prefixName   3.0 = Just "k"
prefixName   6.0 = Just "M"
prefixName   9.0 = Just "G"
prefixName  12.0 = Just "T"
prefixName  15.0 = Just "P"
prefixName  18.0 = Just "E"
prefixName     _ = Nothing

-- | Helper to show exponents in superscript notation.
prettyExponent :: Number → String
prettyExponent -5.0 = "⁻⁵"
prettyExponent -4.0 = "⁻⁴"
prettyExponent -3.0 = "⁻³"
prettyExponent -2.0 = "⁻²"
prettyExponent -1.0 = "⁻¹"
prettyExponent  1.0 = ""
prettyExponent  2.0 = "²"
prettyExponent  3.0 = "³"
prettyExponent  4.0 = "⁴"
prettyExponent  5.0 = "⁵"
prettyExponent exp = "^(" <> show exp <> ")"

-- | A human-readable `String` representation of a `DerivedUnit`, including
-- | a prefix string if the unit needs to be combined with a numerical value.
toStringWithPrefix :: DerivedUnit → { prefix :: String, value :: String }
toStringWithPrefix (DerivedUnit us) =
  { value: unitString
  , prefix: "" -- TODO
  }
  where
    prefixName' exp = fromMaybe ("10^" <> show exp <> "·") (prefixName exp)

    withExp { prefix, baseUnit, exponent } =
      prefixName' prefix <> shortName baseUnit <> prettyExponent exponent

    usSorted = sortBy (comparing (\rec → -rec.exponent)) us
    splitted = span (\rec → rec.exponent >= 0.0) usSorted
    positiveUs = splitted.init
    negativeUs = sortBy (comparing _.exponent) splitted.rest
    reverseExp rec = rec { exponent = -rec.exponent }

    positiveUsStr = intercalate "·" (withExp <$> positiveUs)
    negativeUsStr = intercalate "·" (withExp <$> negativeUs)
    negativeUsStr' = intercalate "·" ((withExp <<< reverseExp) <$> negativeUs)

    unitString =
      case positiveUs of
        Nil → negativeUsStr
        _   → case negativeUs of
                Nil → positiveUsStr
                n : Nil → positiveUsStr <> "/" <> negativeUsStr'
                ns → positiveUsStr <> "/(" <> negativeUsStr' <> ")"

-- | A human-readable `String` representation of a `DerivedUnit`.
toString :: DerivedUnit → String
toString = _.value <<< toStringWithPrefix

-- | Raise a unit to the given power.
power :: DerivedUnit → Number → DerivedUnit
power u n = DerivedUnit $ update <$> runDerivedUnit u
  where
    update rec = rec { exponent = rec.exponent * n }

infixl 9 power as .^

-- | Divide two units.
divideUnits :: DerivedUnit → DerivedUnit → DerivedUnit
divideUnits du1 du2 = du1 <> du2 .^ (-1.0)

infixl 6 divideUnits as ./

-- | A helper (dimensionless) unit, used internally.
-- | (or dimensionless) values.
unity' :: BaseUnit
unity' = BaseUnit { short: "unity", long: "unity", unitType: Standard }

-- | A `DerivedUnit` corresponding to `1`, i.e. the unit of scalar
-- | (or dimensionless) values.
unity :: DerivedUnit
unity = DerivedUnit Nil

-- | Convert a `BaseUnit` to a `DerivedUnit`.
fromBaseUnit :: BaseUnit → DerivedUnit
fromBaseUnit = DerivedUnit <<< singleton <<< (\bu → { prefix: 0.0, baseUnit: bu, exponent: 1.0 })

atto :: DerivedUnit → DerivedUnit
atto = withPrefix (-18.0)

femto :: DerivedUnit → DerivedUnit
femto = withPrefix (-15.0)

pico :: DerivedUnit → DerivedUnit
pico = withPrefix (-12.0)

nano :: DerivedUnit → DerivedUnit
nano = withPrefix (-9.0)

micro :: DerivedUnit → DerivedUnit
micro = withPrefix (-6.0)

milli :: DerivedUnit → DerivedUnit
milli = withPrefix (-3.0)

centi :: DerivedUnit → DerivedUnit
centi = withPrefix (-2.0)

deci :: DerivedUnit → DerivedUnit
deci = withPrefix (-1.0)

hecto :: DerivedUnit → DerivedUnit
hecto = withPrefix 2.0

kilo :: DerivedUnit → DerivedUnit
kilo = withPrefix 3.0

mega :: DerivedUnit → DerivedUnit
mega = withPrefix 6.0

giga :: DerivedUnit → DerivedUnit
giga = withPrefix 9.0

tera :: DerivedUnit → DerivedUnit
tera = withPrefix 12.0

peta :: DerivedUnit → DerivedUnit
peta = withPrefix 15.0

exa :: DerivedUnit → DerivedUnit
exa = withPrefix 18.0
