import * as React from "react";
import { SafeAreaView, StatusBar } from "react-native";
import { createAppContainer } from "react-navigation";
import { createStackNavigator } from "react-navigation-stack";
import { createClient, Provider } from "urql";
import { padding } from "./src/common/vars";
import { BrowserScreen } from "./src/screens/Browser";
import { CommentsList } from "./src/screens/CommentsList";
import { CommentsSink } from "./src/screens/CommentsSink";
import { NewsList } from "./src/screens/NewsList";

const client = createClient({
  url: "https://www.graphqlhub.com/graphql"
});

// TODO: parse <pre> id: 21212445

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
    }
  }
);

const NavigationContainer = createAppContainer(AppNavigator);

export default function AppWrapper() {
  return (
    <Provider value={client}>
      <StatusBar barStyle={"light-content"} />
      <SafeAreaView style={{ flex: 1, padding, backgroundColor: "black" }}>
        <NavigationContainer />
      </SafeAreaView>
    </Provider>
  );
}
