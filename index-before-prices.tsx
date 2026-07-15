import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Keyboard,
  KeyboardAvoidingView,
  Linking,
  Platform,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';

import {
  CitySuggestion,
  searchCities,
} from '../../lib/citySearch';
import {
  CityDetails,
  getCityDetails,
} from '../../lib/cityDetails';
import {
  DiscoveredPlace,
  discoverPlaces,
} from '../../lib/discoverPlaces';
import {
  PlaceDetails,
  getPlaceDetails,
} from '../../lib/placeDetails';

type AppStep = 'setup' | 'results' | 'detail';

type StepperProps = {
  label: string;
  value: number;
  min: number;
  max: number;
  onChange: (value: number) => void;
};

const radiusOptions = [20, 40, 60, 100];


function formatChildAge(age: number) {
  if (age === 0) {
    return 'Do 1 roka';
  }

  if (age === 1) {
    return '1 rok';
  }

  if (age >= 2 && age <= 4) {
    return `${age} roky`;
  }

  return `${age} rokov`;
}

function Stepper({
  label,
  value,
  min,
  max,
  onChange,
}: StepperProps) {
  return (
    <View style={styles.stepperRow}>
      <Text style={styles.stepperLabel}>{label}</Text>

      <View style={styles.stepperControls}>
        <Pressable
          disabled={value <= min}
          onPress={() => onChange(Math.max(min, value - 1))}
          style={[
            styles.stepperButton,
            value <= min && styles.stepperButtonDisabled,
          ]}
        >
          <Text style={styles.stepperButtonText}>−</Text>
        </Pressable>

        <Text style={styles.stepperValue}>{value}</Text>

        <Pressable
          disabled={value >= max}
          onPress={() => onChange(Math.min(max, value + 1))}
          style={[
            styles.stepperButton,
            value >= max && styles.stepperButtonDisabled,
          ]}
        >
          <Text style={styles.stepperButtonText}>+</Text>
        </Pressable>
      </View>
    </View>
  );
}

function SummerBackground() {
  return (
    <View pointerEvents="none" style={StyleSheet.absoluteFill}>
      <View style={styles.sun} />
      <Text style={styles.flowerLeft}>🌼</Text>
      <Text style={styles.flowerRight}>🌸</Text>

      <View style={styles.cloudOne} />
      <View style={styles.cloudTwo} />

      <View style={styles.waveBack} />
      <View style={styles.waveFront} />
    </View>
  );
}

export default function HomeScreen() {
  const [step, setStep] = useState<AppStep>('setup');

  const [city, setCity] = useState('');
  const [cityFocused, setCityFocused] = useState(false);
  const [selectedCity, setSelectedCity] =
    useState<CitySuggestion | null>(null);
  const [citySuggestions, setCitySuggestions] = useState<
    CitySuggestion[]
  >([]);
  const [citySearchLoading, setCitySearchLoading] =
    useState(false);
  const [citySearchError, setCitySearchError] = useState('');

  const [adults, setAdults] = useState(2);
  const [childrenCount, setChildrenCount] = useState(1);
  const [childrenAges, setChildrenAges] = useState<number[]>([4]);

  const [radius, setRadius] = useState(40);
  const [selectedCityDetails, setSelectedCityDetails] =
    useState<CityDetails | null>(null);
  const [places, setPlaces] = useState<DiscoveredPlace[]>([]);
  const [placesLoading, setPlacesLoading] = useState(false);
  const [placesError, setPlacesError] = useState('');
  const [usedRadiusKm, setUsedRadiusKm] = useState<number | null>(null);
  const [savedTips, setSavedTips] = useState<string[]>([]);
  const [activePlace, setActivePlace] =
    useState<DiscoveredPlace | null>(null);
  const [placeDetails, setPlaceDetails] =
    useState<PlaceDetails | null>(null);
  const [placeDetailsLoading, setPlaceDetailsLoading] =
    useState(false);
  const [placeDetailsError, setPlaceDetailsError] =
    useState('');

  useEffect(() => {
    const query = city.trim();

    if (!cityFocused || query.length < 2 || selectedCity) {
      setCitySuggestions([]);
      setCitySearchLoading(false);
      setCitySearchError('');
      return;
    }

    let ignoreResult = false;

    const timer = setTimeout(async () => {
      setCitySearchLoading(true);
      setCitySearchError('');

      try {
        const suggestions = await searchCities(query);

        if (!ignoreResult) {
          setCitySuggestions(suggestions);
        }
      } catch (error) {
        if (!ignoreResult) {
          setCitySuggestions([]);
          setCitySearchError(
            error instanceof Error
              ? error.message
              : 'Mesto sa nepodarilo vyhľadať.',
          );
        }
      } finally {
        if (!ignoreResult) {
          setCitySearchLoading(false);
        }
      }
    }, 400);

    return () => {
      ignoreResult = true;
      clearTimeout(timer);
    };
  }, [city, cityFocused, selectedCity]);

  const canContinue =
    selectedCity !== null &&
    adults >= 1 &&
    childrenCount >= 1 &&
    childrenAges.length === childrenCount;

  function updateChildrenCount(nextValue: number) {
    const safeValue = Math.min(6, Math.max(1, nextValue));

    setChildrenCount(safeValue);

    setChildrenAges((currentAges) => {
      if (safeValue > currentAges.length) {
        return [
          ...currentAges,
          ...Array(safeValue - currentAges.length).fill(4),
        ];
      }

      return currentAges.slice(0, safeValue);
    });
  }

  function updateChildAge(index: number, nextAge: number) {
    setChildrenAges((currentAges) =>
      currentAges.map((age, currentIndex) =>
        currentIndex === index
          ? Math.min(17, Math.max(0, nextAge))
          : age,
      ),
    );
  }

  function selectCity(suggestion: CitySuggestion) {
    setCity(suggestion.name);
    setSelectedCity(suggestion);
    setCitySuggestions([]);
    setCityFocused(false);
    setCitySearchError('');
    Keyboard.dismiss();
  }

  function handleCityChange(value: string) {
    setCity(value);
    setSelectedCity(null);
    setCityFocused(true);
  }

  function toggleSavedTip(tipId: string) {
    setSavedTips((currentTips) =>
      currentTips.includes(tipId)
        ? currentTips.filter((id) => id !== tipId)
        : [...currentTips, tipId],
    );
  }

  async function handleOpenPlace(place: DiscoveredPlace) {
    setActivePlace(place);
    setPlaceDetails(null);
    setPlaceDetailsError('');
    setPlaceDetailsLoading(true);
    setStep('detail');

    try {
      const details = await getPlaceDetails(place.placeId);
      setPlaceDetails(details);
    } catch (error) {
      setPlaceDetailsError(
        error instanceof Error
          ? error.message
          : 'Detail výletu sa nepodarilo načítať.',
      );
    } finally {
      setPlaceDetailsLoading(false);
    }
  }

  async function openExternalUrl(url: string) {
    try {
      await Linking.openURL(url);
    } catch {
      setPlaceDetailsError(
        'Odkaz sa nepodarilo otvoriť v mobile.',
      );
    }
  }

  async function handleFindTrips() {
    if (!selectedCity) {
      return;
    }

    Keyboard.dismiss();
    setPlacesLoading(true);
    setPlacesError('');

    try {
      const cityDetails = await getCityDetails(
        selectedCity.placeId,
      );

      setSelectedCityDetails(cityDetails);

      const result = await discoverPlaces({
        latitude: cityDetails.latitude,
        longitude: cityDetails.longitude,
        radiusKm: radius,
      });

      setPlaces(result.places);
      setUsedRadiusKm(result.search.usedRadiusKm);
      setStep('results');
    } catch (error) {
      setPlaces([]);
      setPlacesError(
        error instanceof Error
          ? error.message
          : 'Výlety sa nepodarilo načítať.',
      );
    } finally {
      setPlacesLoading(false);
    }
  }

  if (step === 'detail' && activePlace) {
    const isSaved = savedTips.includes(activePlace.placeId);

    return (
      <View style={styles.root}>
        <StatusBar style="dark" />
        <SummerBackground />

        <SafeAreaView style={styles.safeArea}>
          <ScrollView
            contentContainerStyle={styles.detailContent}
            showsVerticalScrollIndicator={false}
          >
            <Pressable
              onPress={() => setStep('results')}
              style={styles.backButton}
            >
              <Text style={styles.backButtonText}>
                ← Späť na výlety
              </Text>
            </Pressable>

            <View style={styles.detailHero}>
              <View style={styles.detailEmojiBox}>
                <Text style={styles.detailEmoji}>
                  {activePlace.emoji}
                </Text>
              </View>

              <Text style={styles.detailTitle}>
                {activePlace.name}
              </Text>

              <Text style={styles.detailAddress}>
                {activePlace.formattedAddress}
              </Text>

              <View style={styles.detailTagsRow}>
                <Text style={styles.tipTag}>
                  {activePlace.category}
                </Text>
                <Text style={styles.detailDistance}>
                  {activePlace.distanceKm} km vzdušnou čiarou
                </Text>
              </View>
            </View>

            {placeDetailsLoading && (
              <View style={styles.detailLoadingCard}>
                <ActivityIndicator
                  size="large"
                  color="#168DBB"
                />
                <Text style={styles.detailLoadingText}>
                  Načítavam otváracie hodiny a podrobnosti…
                </Text>
              </View>
            )}

            {!placeDetailsLoading &&
              placeDetailsError.length > 0 && (
                <View style={styles.detailErrorCard}>
                  <Text style={styles.detailErrorTitle}>
                    Detail sa nepodarilo načítať
                  </Text>
                  <Text style={styles.detailErrorText}>
                    {placeDetailsError}
                  </Text>
                  <Pressable
                    onPress={() => handleOpenPlace(activePlace)}
                    style={styles.retryButton}
                  >
                    <Text style={styles.retryButtonText}>
                      Skúsiť znova
                    </Text>
                  </Pressable>
                </View>
              )}

            {!placeDetailsLoading && placeDetails && (
              <>
                <View style={styles.detailQuickRow}>
                  <View style={styles.detailQuickCard}>
                    <Text style={styles.detailQuickIcon}>🕒</Text>
                    <Text style={styles.detailQuickLabel}>
                      Aktuálne
                    </Text>
                    <Text
                      style={[
                        styles.detailQuickValue,
                        placeDetails.openNow === true &&
                          styles.openValue,
                        placeDetails.openNow === false &&
                          styles.closedValue,
                      ]}
                    >
                      {placeDetails.openNow === true
                        ? 'Otvorené'
                        : placeDetails.openNow === false
                          ? 'Zatvorené'
                          : placeDetails.businessStatusLabel ??
                            'Neznáme'}
                    </Text>
                  </View>

                  <View style={styles.detailQuickCard}>
                    <Text style={styles.detailQuickIcon}>⭐</Text>
                    <Text style={styles.detailQuickLabel}>
                      Hodnotenie
                    </Text>
                    <Text style={styles.detailQuickValue}>
                      {placeDetails.rating !== null
                        ? `${placeDetails.rating.toFixed(1)} / 5`
                        : 'Bez údajov'}
                    </Text>
                    {placeDetails.userRatingCount > 0 && (
                      <Text style={styles.detailQuickHint}>
                        {placeDetails.userRatingCount} hodnotení
                      </Text>
                    )}
                  </View>
                </View>

                <View style={styles.detailSection}>
                  <Text style={styles.detailSectionTitle}>
                    🕒 Otváracie hodiny
                  </Text>

                  {placeDetails.openingHours.length > 0 ? (
                    placeDetails.openingHours.map((line) => (
                      <Text
                        key={line}
                        style={styles.openingHoursLine}
                      >
                        {line}
                      </Text>
                    ))
                  ) : (
                    <Text style={styles.detailSectionText}>
                      Otváracie hodiny Google pre toto miesto
                      neuvádza. Pred cestou ich overte na
                      oficiálnej stránke.
                    </Text>
                  )}
                </View>

                <View style={styles.detailSection}>
                  <Text style={styles.detailSectionTitle}>
                    💶 Cena a vstupné
                  </Text>

                  <Text style={styles.detailSectionText}>
                    {placeDetails.priceLabel
                      ? `Cenová úroveň podľa Google: ${placeDetails.priceLabel}.`
                      : 'Presné vstupné Google pre toto miesto neposkytuje.'}
                  </Text>

                  <Text style={styles.detailMutedText}>
                    Aktuálny cenník overíme cez oficiálnu stránku
                    miesta. Neskôr pridáme samostatný modul na
                    získavanie cien.
                  </Text>
                </View>

                {(placeDetails.phone ||
                  placeDetails.businessStatusLabel) && (
                  <View style={styles.detailSection}>
                    <Text style={styles.detailSectionTitle}>
                      ℹ️ Dôležité informácie
                    </Text>

                    {placeDetails.businessStatusLabel && (
                      <Text style={styles.detailSectionText}>
                        Prevádzka: {placeDetails.businessStatusLabel}
                      </Text>
                    )}

                    {placeDetails.phone && (
                      <Pressable
                        onPress={() =>
                          openExternalUrl(
                            `tel:${placeDetails.phone}`,
                          )
                        }
                      >
                        <Text style={styles.detailLinkText}>
                          Telefón: {placeDetails.phone}
                        </Text>
                      </Pressable>
                    )}
                  </View>
                )}

                <View style={styles.detailActions}>
                  {placeDetails.websiteUrl && (
                    <Pressable
                      onPress={() =>
                        openExternalUrl(
                          placeDetails.websiteUrl!,
                        )
                      }
                      style={styles.primaryActionButton}
                    >
                      <Text style={styles.primaryActionText}>
                        Otvoriť oficiálnu stránku
                      </Text>
                    </Pressable>
                  )}

                  {placeDetails.googleMapsUrl && (
                    <Pressable
                      onPress={() =>
                        openExternalUrl(
                          placeDetails.googleMapsUrl!,
                        )
                      }
                      style={styles.secondaryActionButton}
                    >
                      <Text style={styles.secondaryActionText}>
                        Otvoriť v Google Maps
                      </Text>
                    </Pressable>
                  )}

                  <Pressable
                    onPress={() =>
                      toggleSavedTip(activePlace.placeId)
                    }
                    style={[
                      styles.saveButton,
                      isSaved && styles.saveButtonActive,
                    ]}
                  >
                    <Text
                      style={[
                        styles.saveButtonText,
                        isSaved &&
                          styles.saveButtonTextActive,
                      ]}
                    >
                      {isSaved
                        ? '❤️ Uložené'
                        : '🤍 Uložiť výlet'}
                    </Text>
                  </Pressable>
                </View>

                <View style={styles.transportComingCard}>
                  <Text style={styles.transportComingTitle}>
                    🚗 Doprava bude nasledovať
                  </Text>
                  <Text style={styles.transportComingText}>
                    V ďalšom module tu doplníme skutočný čas
                    autom, kilometre po ceste, vlak, autobus,
                    prestupy a chôdzu.
                  </Text>
                </View>
              </>
            )}
          </ScrollView>
        </SafeAreaView>
      </View>
    );
  }

  if (step === 'results') {
    return (
      <View style={styles.root}>
        <StatusBar style="dark" />
        <SummerBackground />

        <SafeAreaView style={styles.safeArea}>
          <ScrollView
            contentContainerStyle={styles.resultsContent}
            showsVerticalScrollIndicator={false}
          >
            <Pressable
              onPress={() => setStep('setup')}
              style={styles.backButton}
            >
              <Text style={styles.backButtonText}>
                ← Upraviť rodinu
              </Text>
            </Pressable>

            <View style={styles.resultsHeadingRow}>
              <View style={styles.resultsHeadingText}>
                <Text style={styles.brandSmall}>
                  RODINNÝ RADAR
                </Text>
                <Text style={styles.resultsTitle}>
                  Tipy pre vás
                </Text>
              </View>

              <Text style={styles.compassEmoji}>🧭</Text>
            </View>

            <View style={styles.familySummary}>
              <Text style={styles.familySummaryTitle}>
                Vaša výprava
              </Text>

              <Text style={styles.familySummaryText}>
                📍 {selectedCityDetails?.formattedAddress ??
                  selectedCity?.fullText ??
                  city}
              </Text>

              <Text style={styles.familySummaryText}>
                🔎 Hľadaný okruh: do {usedRadiusKm ?? radius} km
              </Text>

              <Text style={styles.familySummaryText}>
                👨‍👩‍👧‍👦 {adults} dospelí • {childrenCount}{' '}
                {childrenCount === 1 ? 'dieťa' : 'deti'}
              </Text>

              <Text style={styles.familySummaryText}>
                🎂 {childrenAges.map(formatChildAge).join(' • ')}
              </Text>
            </View>

            {radius > 50 && (
              <Text style={styles.demoText}>
                Pri voľbe {radius} km teraz hľadáme prvých 50 km.
                Väčší okruh rozšírime ďalším modulom.
              </Text>
            )}

            {places.length === 0 ? (
              <View style={styles.emptyCard}>
                <Text style={styles.emptyEmoji}>🧭</Text>
                <Text style={styles.emptyTitle}>
                  V tomto okruhu sme nenašli vhodné miesta
                </Text>
                <Text style={styles.emptyText}>
                  Skús väčší okruh alebo iné východiskové mesto.
                </Text>
              </View>
            ) : (
              places.map((place) => {
                const isSaved = savedTips.includes(place.placeId);

                return (
                  <View key={place.placeId} style={styles.tipCard}>
                    <View style={styles.tipTopRow}>
                      <View style={styles.tipEmojiBox}>
                        <Text style={styles.tipEmoji}>
                          {place.emoji}
                        </Text>
                      </View>

                      <View style={styles.tipHeading}>
                        <Text style={styles.tipTitle}>
                          {place.name}
                        </Text>

                        <Text style={styles.tipLocation}>
                          {place.city || place.formattedAddress}
                          {' • '}
                          {place.distanceKm} km vzdušnou čiarou
                        </Text>
                      </View>
                    </View>

                    <View style={styles.tipMetaRow}>
                      <Text style={styles.tipTag}>
                        {place.category}
                      </Text>

                      <Text style={styles.tipPrice}>
                        {place.countryCode}
                      </Text>
                    </View>

                    <Pressable
                      onPress={() => handleOpenPlace(place)}
                      style={styles.detailsButton}
                    >
                      <Text style={styles.detailsButtonText}>
                        Zobraziť podrobnosti →
                      </Text>
                    </Pressable>

                    <Pressable
                      onPress={() => toggleSavedTip(place.placeId)}
                      style={[
                        styles.saveButton,
                        isSaved && styles.saveButtonActive,
                      ]}
                    >
                      <Text
                        style={[
                          styles.saveButtonText,
                          isSaved && styles.saveButtonTextActive,
                        ]}
                      >
                        {isSaved
                          ? '❤️ Uložené'
                          : '🤍 Uložiť výlet'}
                      </Text>
                    </Pressable>
                  </View>
                );
              })
            )}

            <Text style={styles.savedCounter}>
              Uložené výlety: {savedTips.length}
            </Text>
          </ScrollView>
        </SafeAreaView>
      </View>
    );
  }

  return (
    <View style={styles.root}>
      <StatusBar style="dark" />
      <SummerBackground />

      <SafeAreaView style={styles.safeArea}>
        <KeyboardAvoidingView
          style={styles.keyboardView}
          behavior={
            Platform.OS === 'ios' ? 'padding' : undefined
          }
        >
          <ScrollView
            contentContainerStyle={styles.setupContent}
            keyboardShouldPersistTaps="handled"
            showsVerticalScrollIndicator={false}
          >
            <View style={styles.header}>
              <View>
                <Text style={styles.brandSmall}>
                  RODINNÝ RADAR
                </Text>

                <Text style={styles.mainTitle}>
                  Kam vyrazíme?
                </Text>

                <Text style={styles.mainSubtitle}>
                  Nastavte rodinu a nájdeme vám najlepšie letné
                  zážitky.
                </Text>
              </View>

              <Text style={styles.headerEmoji}>☀️</Text>
            </View>

            <View style={styles.formCard}>
              <Text style={styles.sectionTitle}>
                📍 Odkiaľ vyrážate?
              </Text>

              <TextInput
                value={city}
                onChangeText={handleCityChange}
                onFocus={() => setCityFocused(true)}
                onBlur={() => {
                  setTimeout(
                    () => setCityFocused(false),
                    180,
                  );
                }}
                placeholder="Začnite písať mesto alebo obec"
                placeholderTextColor="#879BA7"
                autoCapitalize="words"
                autoCorrect={false}
                style={styles.cityInput}
              />

              {citySearchLoading && (
                <View style={styles.cityStatusRow}>
                  <ActivityIndicator
                    size="small"
                    color="#168DBB"
                  />
                  <Text style={styles.cityStatusText}>
                    Hľadám mestá a obce…
                  </Text>
                </View>
              )}

              {!citySearchLoading &&
                citySearchError.length > 0 && (
                  <Text style={styles.cityErrorText}>
                    {citySearchError}
                  </Text>
                )}

              {!citySearchLoading &&
                selectedCity &&
                cityFocused && (
                  <View style={styles.selectedCityBox}>
                    <Text style={styles.selectedCityCheck}>
                      ✓
                    </Text>
                    <View style={styles.suggestionContent}>
                      <Text style={styles.suggestionText}>
                        {selectedCity.name}
                      </Text>
                      <Text style={styles.suggestionArea}>
                        {selectedCity.area}
                      </Text>
                    </View>
                  </View>
                )}

              {citySuggestions.length > 0 && (
                <View style={styles.suggestionsBox}>
                  {citySuggestions.map(
                    (suggestion, index) => (
                      <Pressable
                        key={suggestion.placeId}
                        onPressIn={() =>
                          selectCity(suggestion)
                        }
                        style={[
                          styles.suggestionItem,
                          index ===
                            citySuggestions.length - 1 &&
                            styles.suggestionItemLast,
                        ]}
                      >
                        <Text style={styles.suggestionPin}>
                          📍
                        </Text>

                        <View
                          style={styles.suggestionContent}
                        >
                          <Text style={styles.suggestionText}>
                            {suggestion.name}
                          </Text>

                          <Text style={styles.suggestionArea}>
                            {suggestion.area}
                          </Text>
                        </View>
                      </Pressable>
                    ),
                  )}
                </View>
              )}

              {city.length >= 2 &&
                !citySearchLoading &&
                !selectedCity &&
                cityFocused &&
                citySuggestions.length === 0 &&
                citySearchError.length === 0 && (
                  <Text style={styles.noCityText}>
                    Nenašlo sa vhodné mesto alebo obec.
                  </Text>
                )}

              <Text style={styles.sectionTitle}>
                👨‍👩‍👧‍👦 Kto ide na výlet?
              </Text>

              <View style={styles.familyBox}>
                <Stepper
                  label="Dospelí"
                  value={adults}
                  min={1}
                  max={8}
                  onChange={setAdults}
                />

                <View style={styles.divider} />

                <Stepper
                  label="Deti"
                  value={childrenCount}
                  min={1}
                  max={6}
                  onChange={updateChildrenCount}
                />
              </View>

              <Text style={styles.sectionTitle}>
                🎂 Aký vek majú deti?
              </Text>

              <View style={styles.childrenBox}>
                {childrenAges.map((age, index) => (
                  <View
                    key={`child-${index}`}
                    style={[
                      styles.childAgeRow,
                      index === childrenAges.length - 1 &&
                        styles.childAgeRowLast,
                    ]}
                  >
                    <View style={styles.childInfo}>
                      <View style={styles.childNumberCircle}>
                        <Text style={styles.childNumberText}>
                          {index + 1}
                        </Text>
                      </View>

                      <View>
                        <Text style={styles.childTitle}>
                          Dieťa {index + 1}
                        </Text>

                        <Text style={styles.childAgeText}>
                          {formatChildAge(age)}
                        </Text>
                      </View>
                    </View>

                    <View
                      style={styles.smallStepperControls}
                    >
                      <Pressable
                        disabled={age <= 0}
                        onPress={() =>
                          updateChildAge(index, age - 1)
                        }
                        style={[
                          styles.smallStepperButton,
                          age <= 0 &&
                            styles.stepperButtonDisabled,
                        ]}
                      >
                        <Text
                          style={styles.smallStepperText}
                        >
                          −
                        </Text>
                      </Pressable>

                      <Text style={styles.ageNumber}>
                        {age}
                      </Text>

                      <Pressable
                        disabled={age >= 17}
                        onPress={() =>
                          updateChildAge(index, age + 1)
                        }
                        style={[
                          styles.smallStepperButton,
                          age >= 17 &&
                            styles.stepperButtonDisabled,
                        ]}
                      >
                        <Text
                          style={styles.smallStepperText}
                        >
                          +
                        </Text>
                      </Pressable>
                    </View>
                  </View>
                ))}
              </View>

              <Text style={styles.sectionTitle}>
                🚗 Ako ďaleko môžete ísť?
              </Text>

              <View style={styles.radiusRow}>
                {radiusOptions.map((option) => {
                  const selected = radius === option;

                  return (
                    <Pressable
                      key={option}
                      onPress={() => setRadius(option)}
                      style={[
                        styles.radiusButton,
                        selected &&
                          styles.radiusButtonSelected,
                      ]}
                    >
                      <Text
                        style={[
                          styles.radiusText,
                          selected &&
                            styles.radiusTextSelected,
                        ]}
                      >
                        {option} km
                      </Text>
                    </Pressable>
                  );
                })}
              </View>
            </View>

            <Pressable
              disabled={!canContinue || placesLoading}
              onPress={handleFindTrips}
              style={({ pressed }) => [
                styles.mainButton,
                (!canContinue || placesLoading) &&
                  styles.mainButtonDisabled,
                pressed &&
                  canContinue &&
                  !placesLoading &&
                  styles.buttonPressed,
              ]}
            >
              {placesLoading ? (
                <>
                  <ActivityIndicator
                    size="small"
                    color="#FFFFFF"
                  />
                  <Text style={styles.mainButtonTextLoading}>
                    Hľadám reálne výlety…
                  </Text>
                </>
              ) : (
                <>
                  <Text style={styles.mainButtonText}>
                    Nájsť rodinné zážitky
                  </Text>
                  <Text style={styles.mainButtonArrow}>→</Text>
                </>
              )}
            </Pressable>

            {placesError.length > 0 && (
              <Text style={styles.placesErrorText}>
                {placesError}
              </Text>
            )}

            {!canContinue && (
              <Text style={styles.helpText}>
                Napíšte mesto a vyberte ho zo zoznamu.
              </Text>
            )}

            <Text style={styles.bottomText}>
              🌊 Menej hľadania, viac leta s rodinou.
            </Text>
          </ScrollView>
        </KeyboardAvoidingView>
      </SafeAreaView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: '#EAF8FF',
  },
  safeArea: {
    flex: 1,
  },
  keyboardView: {
    flex: 1,
  },

  sun: {
    position: 'absolute',
    top: 65,
    right: 25,
    width: 100,
    height: 100,
    borderRadius: 50,
    backgroundColor: '#FFF1A8',
    opacity: 0.7,
  },
  flowerLeft: {
    position: 'absolute',
    top: 160,
    left: 12,
    fontSize: 34,
    opacity: 0.7,
    transform: [{ rotate: '-15deg' }],
  },
  flowerRight: {
    position: 'absolute',
    top: 290,
    right: 8,
    fontSize: 32,
    opacity: 0.65,
    transform: [{ rotate: '15deg' }],
  },
  cloudOne: {
    position: 'absolute',
    top: 95,
    left: -30,
    width: 150,
    height: 55,
    borderRadius: 40,
    backgroundColor: '#FFFFFF',
    opacity: 0.55,
  },
  cloudTwo: {
    position: 'absolute',
    top: 125,
    right: -45,
    width: 135,
    height: 48,
    borderRadius: 40,
    backgroundColor: '#FFFFFF',
    opacity: 0.45,
  },
  waveBack: {
    position: 'absolute',
    bottom: -120,
    left: -100,
    width: 650,
    height: 260,
    borderRadius: 180,
    backgroundColor: '#BFEAFF',
    opacity: 0.75,
    transform: [{ rotate: '-5deg' }],
  },
  waveFront: {
    position: 'absolute',
    bottom: -175,
    right: -120,
    width: 680,
    height: 270,
    borderRadius: 190,
    backgroundColor: '#92D8F7',
    opacity: 0.6,
    transform: [{ rotate: '7deg' }],
  },

  setupContent: {
    paddingHorizontal: 18,
    paddingTop: 22,
    paddingBottom: 55,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    marginBottom: 20,
    paddingHorizontal: 5,
  },
  brandSmall: {
    color: '#2381A7',
    fontSize: 12,
    fontWeight: '900',
    letterSpacing: 1.4,
  },
  mainTitle: {
    color: '#164761',
    fontSize: 34,
    fontWeight: '900',
    marginTop: 4,
  },
  mainSubtitle: {
    color: '#557687',
    fontSize: 15,
    lineHeight: 21,
    maxWidth: 280,
    marginTop: 5,
  },
  headerEmoji: {
    fontSize: 42,
    marginTop: 4,
  },

  formCard: {
    backgroundColor: 'rgba(255,255,255,0.94)',
    borderRadius: 26,
    padding: 18,
    elevation: 5,
    shadowColor: '#2D7898',
    shadowOpacity: 0.12,
    shadowRadius: 15,
    shadowOffset: {
      width: 0,
      height: 8,
    },
  },
  sectionTitle: {
    color: '#164761',
    fontSize: 16,
    fontWeight: '900',
    marginTop: 19,
    marginBottom: 11,
  },
  cityInput: {
    backgroundColor: '#F5FCFF',
    borderColor: '#B9DFEF',
    borderWidth: 2,
    borderRadius: 16,
    color: '#164761',
    fontSize: 16,
    paddingHorizontal: 15,
    paddingVertical: 14,
  },
  cityStatusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 9,
    paddingHorizontal: 4,
  },
  cityStatusText: {
    color: '#557687',
    fontSize: 13,
    marginLeft: 8,
  },
  cityErrorText: {
    color: '#B63C50',
    fontSize: 13,
    lineHeight: 18,
    marginTop: 9,
    paddingHorizontal: 4,
  },
  noCityText: {
    color: '#657E89',
    fontSize: 13,
    marginTop: 9,
    paddingHorizontal: 4,
  },
  selectedCityBox: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#E8F8EF',
    borderColor: '#B8E6C9',
    borderWidth: 1,
    borderRadius: 15,
    paddingHorizontal: 14,
    paddingVertical: 11,
    marginTop: 7,
  },
  selectedCityCheck: {
    color: '#238A55',
    fontSize: 18,
    fontWeight: '900',
    marginRight: 10,
  },
  suggestionsBox: {
    backgroundColor: '#FFFFFF',
    borderWidth: 1,
    borderColor: '#CBE6F2',
    borderRadius: 15,
    marginTop: 7,
    overflow: 'hidden',
    elevation: 6,
  },
  suggestionItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 13,
    borderBottomWidth: 1,
    borderBottomColor: '#E8F3F7',
  },
  suggestionItemLast: {
    borderBottomWidth: 0,
  },
  suggestionPin: {
    fontSize: 17,
    marginRight: 9,
  },
  suggestionContent: {
    flex: 1,
  },
  suggestionText: {
    color: '#244F63',
    fontSize: 15,
    fontWeight: '800',
  },
  suggestionArea: {
    color: '#78909B',
    fontSize: 12,
    marginTop: 2,
  },

  familyBox: {
    backgroundColor: '#F0FAFF',
    borderRadius: 18,
    paddingHorizontal: 15,
    paddingVertical: 5,
  },
  stepperRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 13,
  },
  stepperLabel: {
    color: '#244F63',
    fontSize: 16,
    fontWeight: '800',
  },
  stepperControls: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  stepperButton: {
    width: 38,
    height: 38,
    borderRadius: 19,
    backgroundColor: '#D6F1FC',
    alignItems: 'center',
    justifyContent: 'center',
  },
  stepperButtonDisabled: {
    opacity: 0.3,
  },
  stepperButtonText: {
    color: '#167DA6',
    fontSize: 25,
    fontWeight: '700',
    marginTop: -2,
  },
  stepperValue: {
    color: '#164761',
    fontSize: 20,
    fontWeight: '900',
    minWidth: 45,
    textAlign: 'center',
  },
  divider: {
    height: 1,
    backgroundColor: '#D9EDF5',
  },

  childrenBox: {
    backgroundColor: '#FFF8FB',
    borderRadius: 18,
    paddingHorizontal: 14,
  },
  childAgeRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 13,
    borderBottomWidth: 1,
    borderBottomColor: '#F2DFE8',
  },
  childAgeRowLast: {
    borderBottomWidth: 0,
  },
  childInfo: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  childNumberCircle: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: '#FFDDEB',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 10,
  },
  childNumberText: {
    color: '#A84270',
    fontSize: 15,
    fontWeight: '900',
  },
  childTitle: {
    color: '#5E3650',
    fontSize: 14,
    fontWeight: '800',
  },
  childAgeText: {
    color: '#956C82',
    fontSize: 12,
    marginTop: 2,
  },
  smallStepperControls: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  smallStepperButton: {
    width: 34,
    height: 34,
    borderRadius: 17,
    backgroundColor: '#FFE8F1',
    alignItems: 'center',
    justifyContent: 'center',
  },
  smallStepperText: {
    color: '#B84F7E',
    fontSize: 22,
    fontWeight: '800',
  },
  ageNumber: {
    color: '#5E3650',
    fontSize: 18,
    fontWeight: '900',
    minWidth: 37,
    textAlign: 'center',
  },

  radiusRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  radiusButton: {
    backgroundColor: '#F1FAFE',
    borderColor: '#C7E5F1',
    borderWidth: 2,
    borderRadius: 14,
    paddingHorizontal: 14,
    paddingVertical: 11,
    marginRight: 8,
    marginBottom: 8,
  },
  radiusButtonSelected: {
    backgroundColor: '#279AC8',
    borderColor: '#279AC8',
  },
  radiusText: {
    color: '#417085',
    fontSize: 14,
    fontWeight: '800',
  },
  radiusTextSelected: {
    color: '#FFFFFF',
  },

  mainButton: {
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#168DBB',
    borderRadius: 18,
    paddingVertical: 17,
    marginTop: 19,
    elevation: 4,
  },
  mainButtonDisabled: {
    backgroundColor: '#9FBBC7',
  },
  mainButtonText: {
    color: '#FFFFFF',
    fontSize: 17,
    fontWeight: '900',
  },
  mainButtonArrow: {
    color: '#FFFFFF',
    fontSize: 22,
    fontWeight: '900',
    marginLeft: 10,
  },
  buttonPressed: {
    opacity: 0.75,
    transform: [{ scale: 0.99 }],
  },
  helpText: {
    color: '#657E89',
    textAlign: 'center',
    marginTop: 10,
    fontSize: 13,
  },
  bottomText: {
    color: '#416D80',
    textAlign: 'center',
    marginTop: 20,
    fontSize: 13,
    fontWeight: '700',
  },

  mainButtonTextLoading: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '900',
    marginLeft: 10,
  },
  placesErrorText: {
    color: '#B63C50',
    backgroundColor: '#FFF1F3',
    borderRadius: 14,
    paddingHorizontal: 14,
    paddingVertical: 12,
    marginTop: 12,
    textAlign: 'center',
    fontSize: 13,
    lineHeight: 18,
  },
  emptyCard: {
    backgroundColor: 'rgba(255,255,255,0.94)',
    borderRadius: 21,
    padding: 24,
    alignItems: 'center',
    marginBottom: 16,
    elevation: 3,
  },
  emptyEmoji: {
    fontSize: 38,
    marginBottom: 10,
  },
  emptyTitle: {
    color: '#164761',
    fontSize: 17,
    fontWeight: '900',
    textAlign: 'center',
  },
  emptyText: {
    color: '#6E8793',
    fontSize: 13,
    lineHeight: 19,
    textAlign: 'center',
    marginTop: 7,
  },

  resultsContent: {
    paddingHorizontal: 18,
    paddingTop: 22,
    paddingBottom: 55,
  },
  backButton: {
    alignSelf: 'flex-start',
    backgroundColor: 'rgba(255,255,255,0.8)',
    borderRadius: 13,
    paddingHorizontal: 13,
    paddingVertical: 9,
    marginBottom: 16,
  },
  backButtonText: {
    color: '#147DA5',
    fontSize: 14,
    fontWeight: '800',
  },
  resultsHeadingRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  resultsHeadingText: {
    flex: 1,
  },
  resultsTitle: {
    color: '#164761',
    fontSize: 32,
    fontWeight: '900',
    marginTop: 3,
  },
  compassEmoji: {
    fontSize: 42,
  },
  familySummary: {
    backgroundColor: 'rgba(255,255,255,0.94)',
    borderRadius: 20,
    padding: 17,
    marginTop: 17,
    elevation: 4,
  },
  familySummaryTitle: {
    color: '#164761',
    fontSize: 16,
    fontWeight: '900',
    marginBottom: 7,
  },
  familySummaryText: {
    color: '#4F7180',
    fontSize: 14,
    marginVertical: 3,
    fontWeight: '600',
  },
  demoText: {
    color: '#527485',
    fontSize: 13,
    lineHeight: 19,
    marginVertical: 17,
  },
  tipCard: {
    backgroundColor: 'rgba(255,255,255,0.96)',
    borderRadius: 21,
    padding: 16,
    marginBottom: 14,
    elevation: 4,
  },
  tipTopRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  tipEmojiBox: {
    width: 58,
    height: 58,
    borderRadius: 17,
    backgroundColor: '#E6F7FF',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: 12,
  },
  tipEmoji: {
    fontSize: 30,
  },
  tipHeading: {
    flex: 1,
  },
  tipTitle: {
    color: '#164761',
    fontSize: 17,
    fontWeight: '900',
  },
  tipLocation: {
    color: '#75909C',
    fontSize: 13,
    marginTop: 4,
  },
  tipMetaRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginTop: 14,
  },
  tipTag: {
    color: '#197B9F',
    backgroundColor: '#E4F6FD',
    paddingHorizontal: 10,
    paddingVertical: 6,
    borderRadius: 10,
    fontSize: 12,
    fontWeight: '800',
  },
  tipPrice: {
    color: '#164761',
    fontSize: 14,
    fontWeight: '900',
  },
  saveButton: {
    borderWidth: 2,
    borderColor: '#CDE7F1',
    borderRadius: 13,
    paddingVertical: 11,
    alignItems: 'center',
    marginTop: 14,
  },
  saveButtonActive: {
    backgroundColor: '#FFF0F5',
    borderColor: '#F4BFD2',
  },
  saveButtonText: {
    color: '#477181',
    fontWeight: '900',
  },
  saveButtonTextActive: {
    color: '#BE4F7D',
  },
  savedCounter: {
    color: '#426D7D',
    textAlign: 'center',
    fontWeight: '800',
    marginTop: 5,
  },
  detailContent: {
    paddingHorizontal: 18,
    paddingTop: 22,
    paddingBottom: 55,
  },
  detailHero: {
    backgroundColor: 'rgba(255,255,255,0.96)',
    borderRadius: 24,
    padding: 20,
    alignItems: 'center',
    elevation: 5,
    marginBottom: 16,
  },
  detailEmojiBox: {
    width: 86,
    height: 86,
    borderRadius: 25,
    backgroundColor: '#E6F7FF',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 14,
  },
  detailEmoji: {
    fontSize: 44,
  },
  detailTitle: {
    color: '#164761',
    fontSize: 27,
    fontWeight: '900',
    textAlign: 'center',
  },
  detailAddress: {
    color: '#6B8794',
    fontSize: 14,
    lineHeight: 20,
    textAlign: 'center',
    marginTop: 7,
  },
  detailTagsRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'center',
    alignItems: 'center',
    marginTop: 15,
  },
  detailDistance: {
    color: '#557687',
    fontSize: 12,
    fontWeight: '700',
    marginLeft: 9,
  },
  detailLoadingCard: {
    backgroundColor: 'rgba(255,255,255,0.96)',
    borderRadius: 20,
    padding: 28,
    alignItems: 'center',
    elevation: 4,
  },
  detailLoadingText: {
    color: '#557687',
    marginTop: 13,
    textAlign: 'center',
    fontWeight: '700',
  },
  detailErrorCard: {
    backgroundColor: '#FFF4F4',
    borderRadius: 20,
    padding: 20,
    borderWidth: 1,
    borderColor: '#F1C7C7',
  },
  detailErrorTitle: {
    color: '#9D2F2F',
    fontSize: 17,
    fontWeight: '900',
  },
  detailErrorText: {
    color: '#8B5555',
    fontSize: 14,
    lineHeight: 20,
    marginTop: 7,
  },
  retryButton: {
    backgroundColor: '#B84B4B',
    borderRadius: 13,
    paddingVertical: 12,
    alignItems: 'center',
    marginTop: 15,
  },
  retryButtonText: {
    color: '#FFFFFF',
    fontWeight: '900',
  },
  detailQuickRow: {
    flexDirection: 'row',
    marginHorizontal: -5,
    marginBottom: 6,
  },
  detailQuickCard: {
    flex: 1,
    backgroundColor: 'rgba(255,255,255,0.96)',
    borderRadius: 18,
    padding: 15,
    marginHorizontal: 5,
    elevation: 3,
  },
  detailQuickIcon: {
    fontSize: 24,
  },
  detailQuickLabel: {
    color: '#75909C',
    fontSize: 12,
    fontWeight: '800',
    marginTop: 7,
  },
  detailQuickValue: {
    color: '#164761',
    fontSize: 16,
    fontWeight: '900',
    marginTop: 3,
  },
  detailQuickHint: {
    color: '#75909C',
    fontSize: 11,
    marginTop: 2,
  },
  openValue: {
    color: '#23845E',
  },
  closedValue: {
    color: '#C04E4E',
  },
  detailSection: {
    backgroundColor: 'rgba(255,255,255,0.96)',
    borderRadius: 20,
    padding: 18,
    marginTop: 12,
    elevation: 3,
  },
  detailSectionTitle: {
    color: '#164761',
    fontSize: 17,
    fontWeight: '900',
    marginBottom: 10,
  },
  detailSectionText: {
    color: '#4F7180',
    fontSize: 14,
    lineHeight: 21,
    marginVertical: 2,
  },
  detailMutedText: {
    color: '#78909B',
    fontSize: 12,
    lineHeight: 18,
    marginTop: 8,
  },
  openingHoursLine: {
    color: '#4F7180',
    fontSize: 14,
    lineHeight: 21,
    marginVertical: 2,
  },
  detailLinkText: {
    color: '#168DBB',
    fontSize: 14,
    fontWeight: '800',
    marginTop: 7,
  },
  detailActions: {
    marginTop: 12,
  },
  primaryActionButton: {
    backgroundColor: '#168DBB',
    borderRadius: 15,
    paddingVertical: 15,
    alignItems: 'center',
    marginBottom: 10,
  },
  primaryActionText: {
    color: '#FFFFFF',
    fontSize: 15,
    fontWeight: '900',
  },
  secondaryActionButton: {
    backgroundColor: 'rgba(255,255,255,0.96)',
    borderColor: '#168DBB',
    borderWidth: 2,
    borderRadius: 15,
    paddingVertical: 14,
    alignItems: 'center',
    marginBottom: 10,
  },
  secondaryActionText: {
    color: '#168DBB',
    fontSize: 15,
    fontWeight: '900',
  },
  transportComingCard: {
    backgroundColor: '#E2F4FC',
    borderRadius: 18,
    padding: 17,
    marginTop: 14,
  },
  transportComingTitle: {
    color: '#164761',
    fontSize: 16,
    fontWeight: '900',
  },
  transportComingText: {
    color: '#557687',
    fontSize: 13,
    lineHeight: 19,
    marginTop: 6,
  },
  detailsButton: {
    backgroundColor: '#168DBB',
    borderRadius: 13,
    paddingVertical: 12,
    alignItems: 'center',
    marginTop: 14,
  },
  detailsButtonText: {
    color: '#FFFFFF',
    fontWeight: '900',
  },
});
