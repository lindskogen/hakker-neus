import Constants from "expo-constants";
import * as React from "react";
import { Platform, SafeAreaView, StatusBar } from "react-native";
import { createAppContainer } from "react-navigation";
import { createStackNavigator } from "react-navigation-stack";
import { Provider } from "urql";
import { backgroundDark } from "./src/common/vars";
import { urqlClient } from "./src/lib/urql";
import { BrowserScreen } from "./src/screens/Browser";
import { CommentsList } from "./src/screens/CommentsList";
import { CommentsSink } from "./src/screens/CommentsSink";
import { NewsList } from "./src/screens/NewsList";

const AppNavigator = createStackNavigator(
  {
    Home: {
      screen: NewsList
    },
    Browser: {
      screen: BrowserScreen
    },
    Comments: { screen: CommentsList },
    CommentsTesting: { screen: CommentsSink }
  },
  {
    initialRouteName: "Home",
    headerMode: "none",
    defaultNavigationOptions: {
      gestureResponseDistance: {
        horizontal: 135,
        vertical: 135
      }
    },
    cardStyle: { backgroundColor: backgroundDark}
  }
);

const NavigationContainer = createAppContainer(AppNavigator);

export default function AppWrapper() {
  return (
    <Provider value={urqlClient}>
      <StatusBar barStyle={"light-content"} />
      <SafeAreaView
        style={{
          flex: 1,
          backgroundColor: backgroundDark,
          paddingTop: Platform.OS === "ios" ? 0 : Constants.statusBarHeight
        }}
      >
        <NavigationContainer />
      </SafeAreaView>
    </Provider>
  );
}
