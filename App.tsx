import * as React from "react";
import { StatusBar, View } from "react-native";
import { NavigationContainer } from "@react-navigation/native";
import {
  CardStyleInterpolators,
  createStackNavigator,
  StackNavigationOptions,
} from "@react-navigation/stack";
import { backgroundDark } from "./src/common/vars";
import { CurrentTimeProvider } from "./src/common/CurrentTimeContext";
import { ErrorView } from "./src/components/ErrorView";
import { FullPageView } from "./src/components/FullPageView";
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from "react-native-safe-area-context";
import { NewsListScreen } from "./src/screens/NewsList";
import { CommentsList } from "./src/screens/CommentsList";
import { CommentsSink } from "./src/screens/CommentsSink";
import { ErrorBoundary } from "./src/components/ErrorBoundary";
import { HNStory } from "./src/common/types";
import { QueryClientProvider } from "react-query";
import { queryClient } from "./src/lib/queryClient";

const Stack = createStackNavigator<RootStackParamList>();

export type RootStackParamList = {
  Home: undefined;
  Comments: { id: string; story?: HNStory };
  CommentsTesting: undefined;
};

const screenOptions: StackNavigationOptions = {
  gestureEnabled: true,
  gestureDirection: "horizontal",
  gestureResponseDistance: {
    horizontal: 135,
    vertical: 135,
  },
  cardStyle: { backgroundColor: backgroundDark },
  cardStyleInterpolator: CardStyleInterpolators.forHorizontalIOS,
};

function AppWrapper() {
  const { right, left, top } = useSafeAreaInsets();
  return (
    <ErrorBoundary
      fallback={(error) => (
        <FullPageView backgroundColor={backgroundDark}>
          <ErrorView error={error} />
        </FullPageView>
      )}
    >
      <QueryClientProvider client={queryClient}>
        <CurrentTimeProvider>
          <StatusBar barStyle={"light-content"} />
          <View
            style={{
              flex: 1,
              paddingRight: right,
              paddingLeft: left,
              paddingTop: top,
              paddingBottom: 0,
              backgroundColor: backgroundDark,
            }}
          >
            <Stack.Navigator
              initialRouteName="Home"
              headerMode="none"
              screenOptions={screenOptions}
            >
              <Stack.Screen name="Home" component={NewsListScreen} />
              <Stack.Screen name="Comments" component={CommentsList} />
              <Stack.Screen name="CommentsTesting" component={CommentsSink} />
            </Stack.Navigator>
          </View>
        </CurrentTimeProvider>
      </QueryClientProvider>
    </ErrorBoundary>
  );
}

export default () => (
  <SafeAreaProvider>
    <NavigationContainer>
      <AppWrapper />
    </NavigationContainer>
  </SafeAreaProvider>
);
