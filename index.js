import { AppRegistry } from 'react-native';
import App from './App';
import { useScreens } from 'react-native-screens';

useScreens();

AppRegistry.registerComponent('HackerNeus', () => App);
