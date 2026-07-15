import { StatusBar } from 'expo-status-bar';
import { useMemo, useState } from 'react';
import {
  Keyboard,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';

type AppStep = 'setup' | 'results';

type StepperProps = {
  label: string;
  value: number;
  min: number;
  max: number;
  onChange: (value: number) => void;
};

const cityOptions = [
  'Banská Belá',
  'Banská Štiavnica',
  'Banská Bystrica',
  'Zvolen',
  'Žiar nad Hronom',
  'Žarnovica',
  'Kremnica',
  'Krupina',
  'Detva',
  'Sliač',
  'Dudince',
  'Levice',
  'Brezno',
  'Nová Baňa',
  'Hriňová',
  'Veľký Krtíš',
];

const radiusOptions = [20, 40, 60, 100];

const sampleTips = [
  {
    id: 1,
    emoji: '🏰',
    title: 'Dobrodružstvo na zámku',
    location: 'Banská Štiavnica',
    distance: '8 km',
    price: 'Od 5 €',
    tag: 'Aj pri daždi',
  },
  {
    id: 2,
    emoji: '🦙',
    title: 'Rodinný deň so zvieratami',
    location: 'Žiar nad Hronom',
    distance: '29 km',
    price: 'Rodinné vstupné',
    tag: 'Zvieratá',
  },
  {
    id: 3,
    emoji: '🎪',
    title: 'Letné podujatie pre deti',
    location: 'Zvolen',
    distance: '43 km',
    price: 'Zadarmo',
    tag: 'Víkendová akcia',
  },
];

function normalizeText(text: string) {
  return text
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();
}

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

  const [adults, setAdults] = useState(2);
  const [childrenCount, setChildrenCount] = useState(1);
  const [childrenAges, setChildrenAges] = useState<number[]>([4]);

  const [radius, setRadius] = useState(40);
  const [savedTips, setSavedTips] = useState<number[]>([]);

  const citySuggestions = useMemo(() => {
    if (!cityFocused) {
      return [];
    }

    const search = normalizeText(city.trim());

    if (!search) {
      return cityOptions.slice(0, 6);
    }

    return cityOptions
      .filter((item) => normalizeText(item).includes(search))
      .slice(0, 6);
  }, [city, cityFocused]);

  const canContinue =
    city.trim().length >= 2 &&
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

  function selectCity(selectedCity: string) {
    setCity(selectedCity);
    setCityFocused(false);
    Keyboard.dismiss();
  }

  function toggleSavedTip(tipId: number) {
    setSavedTips((currentTips) =>
      currentTips.includes(tipId)
        ? currentTips.filter((id) => id !== tipId)
        : [...currentTips, tipId],
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
              <Text style={styles.backButtonText}>← Upraviť rodinu</Text>
            </Pressable>

            <View style={styles.resultsHeadingRow}>
              <View style={styles.resultsHeadingText}>
                <Text style={styles.brandSmall}>RODINNÝ RADAR</Text>
                <Text style={styles.resultsTitle}>Tipy pre vás</Text>
              </View>

              <Text style={styles.compassEmoji}>🧭</Text>
            </View>

            <View style={styles.familySummary}>
              <Text style={styles.familySummaryTitle}>
                Vaša výprava
              </Text>

              <Text style={styles.familySummaryText}>
                📍 {city} • do {radius} km
              </Text>

              <Text style={styles.familySummaryText}>
                👨‍👩‍👧‍👦 {adults} dospelí • {childrenCount}{' '}
                {childrenCount === 1 ? 'dieťa' : 'deti'}
              </Text>

              <Text style={styles.familySummaryText}>
                🎂 {childrenAges.map(formatChildAge).join(' • ')}
              </Text>
            </View>

            <Text style={styles.demoText}>
              Toto sú zatiaľ ukážkové výlety. Neskôr ich budeme
              načítavať podľa skutočnej vzdialenosti, dátumu a veku detí.
            </Text>

            {sampleTips.map((tip) => {
              const isSaved = savedTips.includes(tip.id);

              return (
                <View key={tip.id} style={styles.tipCard}>
                  <View style={styles.tipTopRow}>
                    <View style={styles.tipEmojiBox}>
                      <Text style={styles.tipEmoji}>{tip.emoji}</Text>
                    </View>

                    <View style={styles.tipHeading}>
                      <Text style={styles.tipTitle}>{tip.title}</Text>

                      <Text style={styles.tipLocation}>
                        {tip.location} • {tip.distance}
                      </Text>
                    </View>
                  </View>

                  <View style={styles.tipMetaRow}>
                    <Text style={styles.tipTag}>{tip.tag}</Text>
                    <Text style={styles.tipPrice}>{tip.price}</Text>
                  </View>

                  <Pressable
                    onPress={() => toggleSavedTip(tip.id)}
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
                      {isSaved ? '❤️ Uložené' : '🤍 Uložiť výlet'}
                    </Text>
                  </Pressable>
                </View>
              );
            })}

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
          behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        >
          <ScrollView
            contentContainerStyle={styles.setupContent}
            keyboardShouldPersistTaps="handled"
            showsVerticalScrollIndicator={false}
          >
            <View style={styles.header}>
              <View>
                <Text style={styles.brandSmall}>RODINNÝ RADAR</Text>

                <Text style={styles.mainTitle}>
                  Kam vyrazíme?
                </Text>

                <Text style={styles.mainSubtitle}>
                  Nastavte rodinu a nájdeme vám najlepšie letné zážitky.
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
                onChangeText={(value) => {
                  setCity(value);
                  setCityFocused(true);
                }}
                onFocus={() => setCityFocused(true)}
                onBlur={() => {
                  setTimeout(() => setCityFocused(false), 150);
                }}
                placeholder="Začnite písať mesto alebo obec"
                placeholderTextColor="#879BA7"
                autoCapitalize="words"
                style={styles.cityInput}
              />

              {citySuggestions.length > 0 && (
                <View style={styles.suggestionsBox}>
                  {citySuggestions.map((suggestion, index) => (
                    <Pressable
                      key={suggestion}
                      onPressIn={() => selectCity(suggestion)}
                      style={[
                        styles.suggestionItem,
                        index === citySuggestions.length - 1 &&
                          styles.suggestionItemLast,
                      ]}
                    >
                      <Text style={styles.suggestionPin}>📍</Text>
                      <Text style={styles.suggestionText}>
                        {suggestion}
                      </Text>
                    </Pressable>
                  ))}
                </View>
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

                    <View style={styles.smallStepperControls}>
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
                        <Text style={styles.smallStepperText}>−</Text>
                      </Pressable>

                      <Text style={styles.ageNumber}>{age}</Text>

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
                        <Text style={styles.smallStepperText}>+</Text>
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
                        selected && styles.radiusButtonSelected,
                      ]}
                    >
                      <Text
                        style={[
                          styles.radiusText,
                          selected && styles.radiusTextSelected,
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
              disabled={!canContinue}
              onPress={() => {
                Keyboard.dismiss();
                setStep('results');
              }}
              style={({ pressed }) => [
                styles.mainButton,
                !canContinue && styles.mainButtonDisabled,
                pressed && canContinue && styles.buttonPressed,
              ]}
            >
              <Text style={styles.mainButtonText}>
                Nájsť rodinné zážitky
              </Text>

              <Text style={styles.mainButtonArrow}>→</Text>
            </Pressable>

            {!canContinue && (
              <Text style={styles.helpText}>
                Najprv vyberte mesto alebo obec.
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
  suggestionText: {
    color: '#244F63',
    fontSize: 15,
    fontWeight: '700',
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
});