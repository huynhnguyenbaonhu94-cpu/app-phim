import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import NotFound from "@/pages/NotFound";
import { Route, Switch } from "wouter";
import ErrorBoundary from "./components/ErrorBoundary";
import { ThemeProvider } from "./contexts/ThemeContext";
import Home from "./pages/Home";
import { CatalogPage, CategoryDirectoryPage, DirectoryPage, SearchPage } from "@/pages/Catalog";
import DetailPage from "./pages/Detail";
import AccountPage from "./pages/Account";

function Router() {
  return <Switch>
    <Route path="/" component={Home} />
    <Route path="/search" component={SearchPage} />
    <Route path="/account" component={AccountPage} />
    <Route path="/catalog/latest"><CatalogPage kind="latest" /></Route>
    <Route path="/catalog/single"><CatalogPage kind="single" /></Route>
    <Route path="/catalog/series"><CatalogPage kind="series" /></Route>
    <Route path="/catalog/shows"><CatalogPage kind="shows" /></Route>
    <Route path="/catalog/animation"><CatalogPage kind="animation" /></Route>
    <Route path="/catalog/vietsub"><CatalogPage kind="vietsub" /></Route>
    <Route path="/catalog/thuyet-minh"><CatalogPage kind="thuyetminh" /></Route>
    <Route path="/catalog/long-tieng"><CatalogPage kind="longtieng" /></Route>
    <Route path="/catalog/subteam"><CatalogPage kind="subteam" /></Route>
    <Route path="/catalog/theatrical"><CatalogPage kind="theatrical" /></Route>
    <Route path="/catalog/categories"><CategoryDirectoryPage /></Route>
    <Route path="/catalog/countries"><DirectoryPage dimension="countries" /></Route>
    <Route path="/catalog/years"><DirectoryPage dimension="years" /></Route>
    <Route path="/movie/:slug">{(params) => <DetailPage slug={params.slug} />}</Route>
    <Route path="/404" component={NotFound} />
    <Route component={NotFound} />
  </Switch>;
}

export default function App() {
  return <ErrorBoundary><ThemeProvider defaultTheme="dark"><TooltipProvider><Toaster /><Router /></TooltipProvider></ThemeProvider></ErrorBoundary>;
}
