import * as React from "react";
import { StatusBar } from "react-native";
import { createAppContainer, SafeAreaView } from "react-navigation";
import {
  CardStyleInterpolators,
  createStackNavigator
} from "react-navigation-stack";
import { backgroundDark } from "./src/common/vars";
import { CommentsList } from "./src/screens/CommentsList";
import { CommentsSink } from "./src/screens/CommentsSink";
import { NewsListScreen } from "./src/screens/NewsList";

const AppNavigator = createStackNavigator(
  {
    Home: { screen: NewsListScreen },
    Comments: { screen: CommentsList },
    CommentsTesting: { screen: CommentsSink }
  },
  {
    initialRouteName: "Home",
    headerMode: "none",
    defaultNavigationOptions: {
      gestureEnabled: true,
      gestureDirection: "horizontal",
      gestureResponseDistance: {
        horizontal: 135,
        vertical: 135
      },
      cardStyle: { backgroundColor: backgroundDark },
      cardStyleInterpolator: CardStyleInterpolators.forHorizontalIOS
    }
  }
);

const NavigationContainer = createAppContainer(AppNavigator);

export default function AppWrapper() {
  return (
    <>
      <StatusBar barStyle={"light-content"} />
      <SafeAreaView
        forceInset={{ bottom: "never" }}
        style={{
          flex: 1,
          backgroundColor: backgroundDark
        }}
      >
        <NavigationContainer />
      </SafeAreaView>
    </>
  );
}
